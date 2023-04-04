//
// Created by herrylv on 06/5/2022
//

#include "log_producer_manager.h"
#include "cls_log.h"
#include "md5.h"
#include "sds.h"
#include "utils.h"
#include <sys/time.h>

// change from 100ms to 1000s, reduce wake up when app switch to back
#define LOG_PRODUCER_FLUSH_INTERVAL_MS 1000

#define MAX_LOGGROUP_QUEUE_SIZE 1024
#define MIN_LOGGROUP_QUEUE_SIZE 32

#define MAX_MANAGER_FLUSH_COUNT 100 // 10MS * 100
#define MAX_SENDER_FLUSH_COUNT 100  // 10ms * 100

#ifdef WIN32
DWORD WINAPI SendThread(LPVOID param);
#else
void *SendThread(void *param);
#endif

void _generate_pack_id_timestamp(long *timestamp)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    *(timestamp) = ts.tv_nsec;
}

char *_get_pack_id(const char *configName, const char *ip)
{
    long timestamp;
    _generate_pack_id_timestamp(&timestamp);

    char *prefix = (char *)malloc(100 * sizeof(char));
    strcpy(prefix, configName);
    sprintf(prefix, "%s%ld", prefix, timestamp);

    unsigned char md5Buf[16];
    mbedtls_md5((const unsigned char *)prefix, strlen(prefix), md5Buf);
    int loop = 0;
    char *val = (char *)malloc(sizeof(char) * 32);
    memset(val, 0, sizeof(char) * 32);
    for (; loop < 8; ++loop)
    {
        unsigned char a = ((md5Buf[loop]) >> 4) & 0xF, b = (md5Buf[loop]) & 0xF;
        val[loop << 1] = a > 9 ? (a - 10 + 'A') : (a + '0');
        val[(loop << 1) | 1] = b > 9 ? (b - 10 + 'A') : (b + '0');
    }
    return val;
}

void _try_flush_loggroup(ProducerManager *producermgr)
{
    int32_t now_time = time(NULL);

    pthread_mutex_lock(producermgr->lock);
    if (producermgr->builder != NULL && now_time - producermgr->firstLogTime > producermgr->producerconf->packageTimeoutInMS / 1000)
    {
        log_group_builder *builder = producermgr->builder;
        producermgr->builder = NULL;
        pthread_mutex_unlock(producermgr->lock);

        size_t loggroup_size = builder->loggroup_size;
        int rst = log_queue_push(producermgr->loggroup_queue, builder);
        cls_debug_log("try push loggroup to flusher, size : %d, status : %d", (int)loggroup_size, rst);
        if (rst != 0)
        {
            cls_error_log("try push loggroup to flusher failed, force drop this log group, error code : %d", rst);
            if (producermgr->callbackfunc != NULL)
            {
                producermgr->callbackfunc(producermgr->producerconf->topic, LOG_PRODUCER_DROP_ERROR, loggroup_size, 0,
                                                     NULL, "try push loggroup to flusher failed, force drop this log group", NULL, producermgr->user_param);
            }
            log_group_destroy(builder);
        }
        else
        {
            producermgr->totalBufferSize += loggroup_size;
            pthread_cond_signal(producermgr->triger_cond);
        }
    }
    else
    {
        pthread_mutex_unlock(producermgr->lock);
    }
}

#ifdef WIN32
DWORD WINAPI log_producer_flush_thread(LPVOID param)
#else
void *log_producer_flush_thread(void *param)
#endif
{
    ProducerManager *root_producer_manager = (ProducerManager *)param;
    cls_info_log("start run flusher thread, topic : %s", root_producer_manager->producerconf->topic);
    while (root_producer_manager->shutdown == 0)
    {

        pthread_mutex_lock(root_producer_manager->lock);
        COND_WAIT_TIME(root_producer_manager->triger_cond,
                       root_producer_manager->lock,
                       LOG_PRODUCER_FLUSH_INTERVAL_MS);
        pthread_mutex_unlock(root_producer_manager->lock);
        do
        {
            // if send queue is full, skip pack and send data
            if (root_producer_manager->send_param_queue_write - root_producer_manager->send_param_queue_read >= root_producer_manager->send_param_queue_size)
            {
                break;
            }
            void *data = log_queue_trypop(root_producer_manager->loggroup_queue);
            if (data != NULL)
            {
                // process data
                log_group_builder *builder = (log_group_builder *)data;

                ProducerManager *producermgr = (ProducerManager *)builder->private_value;
                pthread_mutex_lock(root_producer_manager->lock);
                producermgr->totalBufferSize -= builder->loggroup_size;
                pthread_mutex_unlock(root_producer_manager->lock);

                ProducerConfig *config = producermgr->producerconf;
                if (config->topic != NULL)
                {
                    AddTopic(builder, config->topic, strlen(config->topic));
                }
                if (config->source != NULL)
                {
                    AddSource(builder, producermgr->source, strlen(producermgr->source));
                }
                if (producermgr->pack_prefix != NULL)
                {
                    AddPackageId(builder, producermgr->pack_prefix, strlen(producermgr->pack_prefix), producermgr->pack_index++);
                }

                lz4_content *lz4_buf = NULL;
                // check compress type
                if (config->compressType == 1)
                {
                    lz4_buf = SerializeWithlz4(builder);
                }
                else
                {
                    lz4_buf = SerializeWithNolz4(builder);
                }

                if (lz4_buf == NULL)
                {
                    cls_error_log("serialize loggroup to proto buf with lz4 failed");
                    if (producermgr->callbackfunc)
                    {
                        producermgr->callbackfunc(producermgr->producerconf->topic, LOG_PRODUCER_DROP_ERROR, builder->loggroup_size, 0,
                                                             NULL, "serialize loggroup to proto buf with lz4 failed", NULL, producermgr->user_param);
                    }
                }
                else
                {
                    pthread_mutex_lock(root_producer_manager->lock);
                    producermgr->totalBufferSize += lz4_buf->length;
                    pthread_mutex_unlock(root_producer_manager->lock);

                    cls_debug_log("push loggroup to sender, topic %s, loggroup size %d, lz4 size %d, now buffer size %d",
                                  config->topic, (int)lz4_buf->raw_length, (int)lz4_buf->length, (int)producermgr->totalBufferSize);
                    // if use multi thread, should change producermgr->send_pool to NULL
                    //apr_pool_t * pool = config->sendThreadCount == 1 ? producermgr->send_pool : NULL;
                    log_producer_send_param *send_param = ConstructSendParam(config, producermgr, lz4_buf, builder);
                    root_producer_manager->send_param_queue[root_producer_manager->send_param_queue_write++ % root_producer_manager->send_param_queue_size] = send_param;
                }
                log_group_destroy(builder);
                continue;
            }
            break;
        } while (1);

        _try_flush_loggroup(root_producer_manager);

        // send data
        if (root_producer_manager->send_threads != NULL)
        {
            // if send thread count > 0, we just push send_param to sender queue
            while (root_producer_manager->send_param_queue_write > root_producer_manager->send_param_queue_read && !CheckLogQueueIsFull(root_producer_manager->send_queue))
            {
                log_producer_send_param *send_param = root_producer_manager->send_param_queue[root_producer_manager->send_param_queue_read++ % root_producer_manager->send_param_queue_size];
                // push always success
                log_queue_push(root_producer_manager->send_queue, send_param);
            }
        }
        else if (root_producer_manager->send_param_queue_write > root_producer_manager->send_param_queue_read)
        {
            // if no sender thread, we send this packet out in flush thread
            log_producer_send_param *send_param = root_producer_manager->send_param_queue[root_producer_manager->send_param_queue_read++ % root_producer_manager->send_param_queue_size];
            SendData(send_param);
        }
    }
    cls_info_log("exit flusher thread, topic : %s", root_producer_manager->producerconf->topic);
    return 0;
}

ProducerManager *ConstructorProducerManager(ProducerConfig *producerconf)
{
    cls_debug_log("create log producer manager : %s", producerconf->topic);
    ProducerManager *producermgr = (ProducerManager *)malloc(sizeof(ProducerManager));
    memset(producermgr, 0, sizeof(ProducerManager));

    producermgr->producerconf = producerconf;

    int64_t base_queue_size = producerconf->maxBufferBytes / (producerconf->logBytesPerPackage + 1) + 10;
    if (base_queue_size < MIN_LOGGROUP_QUEUE_SIZE)
    {
        base_queue_size = MIN_LOGGROUP_QUEUE_SIZE;
    }
    else if (base_queue_size > MAX_LOGGROUP_QUEUE_SIZE)
    {
        base_queue_size = MAX_LOGGROUP_QUEUE_SIZE;
    }

    producermgr->loggroup_queue = ConstructLogQueue(base_queue_size);
    producermgr->send_param_queue_size = base_queue_size * 2;
    producermgr->send_param_queue = malloc(sizeof(log_producer_send_param *) * producermgr->send_param_queue_size);

    if (producerconf->sendThreadCount > 0)
    {
        producermgr->send_thread_count = 0;
        producermgr->send_threads = (pthread_t *)malloc(sizeof(pthread_t) * producerconf->sendThreadCount);
        producermgr->send_queue = ConstructLogQueue(base_queue_size * 2);
        int32_t threadId = 0;
        for (; threadId < producermgr->producerconf->sendThreadCount; ++threadId)
        {
            THREAD_INIT(producermgr->send_threads[threadId], SendThread, producermgr);
        }
    }

    producermgr->triger_cond = InitCond();
    producermgr->lock = InitMutex();
    THREAD_INIT(producermgr->flush_thread, log_producer_flush_thread, producermgr);
    if (producerconf->source != NULL)
    {
        producermgr->source = sdsnew(producerconf->source);
    }
    else
    {
        producermgr->source = sdsnew("undefined");
    }

    if (producermgr->pack_prefix == NULL)
    {
        producermgr->pack_prefix = (char *)malloc(32);
        srand(time(NULL));
        int i = 0;
        for (i = 0; i < 16; ++i)
        {
            producermgr->pack_prefix[i] = rand() % 10 + '0';
        }
        producermgr->pack_prefix[i] = '\0';
    }
    return producermgr;
}

void _push_last_loggroup(ProducerManager *manager)
{
    pthread_mutex_lock(manager->lock);
    log_group_builder *builder = manager->builder;
    manager->builder = NULL;
    if (builder != NULL)
    {
        size_t loggroup_size = builder->loggroup_size;
        cls_debug_log("try push loggroup to flusher, size : %d, log size %d", (int)builder->loggroup_size, (int)builder->grp->logs.now_buffer_len);
        int32_t status = log_queue_push(manager->loggroup_queue, builder);
        if (status != 0)
        {
            cls_error_log("try push loggroup to flusher failed, force drop this log group, error code : %d", status);
            log_group_destroy(builder);
        }
        else
        {
            manager->totalBufferSize += loggroup_size;
            pthread_cond_signal(manager->triger_cond);
        }
    }
    pthread_mutex_unlock(manager->lock);
}

void destroy_log_producer_manager(ProducerManager *manager)
{
    // when destroy instance, flush last loggroup
    _push_last_loggroup(manager);

    cls_info_log("flush out producer loggroup begin");
    int32_t total_wait_count = manager->producerconf->destroyFlusherWaitTimeoutSec > 0 ? manager->producerconf->destroyFlusherWaitTimeoutSec * 100 : MAX_MANAGER_FLUSH_COUNT;
    total_wait_count += manager->producerconf->destroySenderWaitTimeoutSec > 0 ? manager->producerconf->destroySenderWaitTimeoutSec * 100 : MAX_SENDER_FLUSH_COUNT;

#ifdef WIN32
    Sleep(10);
#else
    usleep(10 * 1000);
#endif

    int waitCount = 0;
    while (GetLogQueueSize(manager->loggroup_queue) > 0 ||
           manager->send_param_queue_write - manager->send_param_queue_read > 0 ||
           (manager->send_queue != NULL && GetLogQueueSize(manager->send_queue) > 0))
    {
#ifdef WIN32
        Sleep(10);
#else
        usleep(10 * 1000);
#endif
        if (++waitCount == total_wait_count)
        {
            break;
        }
    }
    if (waitCount == total_wait_count)
    {
        cls_error_log("try flush out producer loggroup error, force exit, now loggroup %d", (int)(GetLogQueueSize(manager->loggroup_queue)));
    }
    else
    {
        cls_info_log("flush out producer loggroup success");
    }
    manager->shutdown = 1;

    // destroy root resources
    pthread_cond_signal(manager->triger_cond);
    cls_info_log("join flush thread begin");
    THREAD_JOIN(manager->flush_thread);
    cls_info_log("join flush thread success");
    if (manager->send_threads != NULL)
    {
        cls_info_log("join sender thread pool begin");
        int32_t threadId = 0;
        for (; threadId < manager->producerconf->sendThreadCount; ++threadId)
        {
            THREAD_JOIN(manager->send_threads[threadId]);
        }
        free(manager->send_threads);
        cls_info_log("join sender thread pool success");
    }
    DeleteCond(manager->triger_cond);
    DestroyLogQueue(manager->loggroup_queue);
    if (manager->send_queue != NULL)
    {
        cls_info_log("flush out sender queue begin");
        while (GetLogQueueSize(manager->send_queue) > 0)
        {
            void *send_param = log_queue_trypop(manager->send_queue);
            if (send_param != NULL)
            {
                SendProcess(send_param);
            }
        }
        DestroyLogQueue(manager->send_queue);
        cls_info_log("flush out sender queue success");
    }
    DestroyMutex(manager->lock);
    if (manager->pack_prefix != NULL)
    {
        free(manager->pack_prefix);
    }
    if (manager->send_param_queue != NULL)
    {
        free(manager->send_param_queue);
    }
    sdsfree(manager->source);
    free(manager);
}

#define LOG_PRODUCER_MANAGER_ADD_LOG_BEGIN                                                     \
    if (producermgr->totalBufferSize > producermgr->producerconf->maxBufferBytes) \
    {                                                                                          \
        return LOG_PRODUCER_DROP_ERROR;                                                        \
    }                                                                                          \
    pthread_mutex_lock(producermgr->lock);                                                          \
    if (producermgr->builder == NULL)                                                     \
    {                                                                                          \
        if (CheckLogQueueIsFull(producermgr->loggroup_queue))                                \
        {                                                                                      \
            pthread_mutex_unlock(producermgr->lock);                                                  \
            return LOG_PRODUCER_DROP_ERROR;                                                    \
        }                                                                                      \
        int32_t now_time = time(NULL);                                                         \
        producermgr->builder = GenerateLogGroup();                                        \
        producermgr->firstLogTime = now_time;                                             \
        producermgr->builder->private_value = producermgr;                           \
    }

#define LOG_PRODUCER_MANAGER_ADD_LOG_END                                                                                                                                                                                                                                                                                             \
    log_group_builder *builder = producermgr->builder;                                                                                                                                                                                                                                                                          \
    int32_t nowTime = time(NULL);                                                                                                                                                                                                                                                                                                    \
    if (flush == 0 && producermgr->builder->loggroup_size < producermgr->producerconf->logBytesPerPackage && nowTime - producermgr->firstLogTime < producermgr->producerconf->packageTimeoutInMS / 1000 && producermgr->builder->grp->logs_count < producermgr->producerconf->logCountPerPackage) \
    {                                                                                                                                                                                                                                                                                                                                \
        pthread_mutex_unlock(producermgr->lock);                                                                                                                                                                                                                                                                                            \
        return LOG_PRODUCER_OK;                                                                                                                                                                                                                                                                                                      \
    }                                                                                                                                                                                                                                                                                                                                \
    int ret = LOG_PRODUCER_OK;                                                                                                                                                                                                                                                                                                       \
    producermgr->builder = NULL;                                                                                                                                                                                                                                                                                                \
    size_t loggroup_size = builder->loggroup_size;                                                                                                                                                                                                                                                                                   \
    cls_debug_log("try push loggroup to flusher, size : %d, log count %d", (int)builder->loggroup_size, (int)builder->grp->logs_count);                                                                                                                                                                                                  \
    int status = log_queue_push(producermgr->loggroup_queue, builder);                                                                                                                                                                                                                                                          \
    if (status != 0)                                                                                                                                                                                                                                                                                                                 \
    {                                                                                                                                                                                                                                                                                                                                \
        cls_error_log("try push loggroup to flusher failed, force drop this log group, error code : %d", status);                                                                                                                                                                                                                    \
        ret = LOG_PRODUCER_DROP_ERROR;                                                                                                                                                                                                                                                                                               \
        log_group_destroy(builder);                                                                                                                                                                                                                                                                                                  \
    }                                                                                                                                                                                                                                                                                                                                \
    else                                                                                                                                                                                                                                                                                                                             \
    {                                                                                                                                                                                                                                                                                                                                \
        producermgr->totalBufferSize += loggroup_size;                                                                                                                                                                                                                                                                          \
        pthread_cond_signal(producermgr->triger_cond);                                                                                                                                                                                                                                                                                  \
    }                                                                                                                                                                                                                                                                                                                                \
    pthread_mutex_unlock(producermgr->lock);                                                                                                                                                                                                                                                                                                \
    return ret;

int
log_producer_manager_add_log(ProducerManager *producermgr,
                                   int64_t logtime,
                                   int32_t pair_count, char **keys,
                                   int32_t *key_lens, char **values,
                                   int32_t *val_lens, int flush, int64_t uuid)
{
    LOG_PRODUCER_MANAGER_ADD_LOG_BEGIN;

    InnerAddLog(producermgr->builder, logtime, pair_count, keys, key_lens, values, val_lens);

    LOG_PRODUCER_MANAGER_ADD_LOG_END;
}
