//
// Created by herrylv on 06/5/2022
//

#include "cls_log_producer_manager.h"
#include "cls_log_persistent_manager.h"
#include "cls_log.h"
#include "cls_md5.h"
#include "cls_sds.h"
#include "cls_utils.h"
#include <sys/time.h>

// change from 100ms to 1000s, reduce wake up when app switch to back
#define CLS_LOG_PRODUCER_FLUSH_INTERVAL_MS 1000

#define CLS_MAX_LOGGROUP_QUEUE_SIZE 1024
#define CLS_MIN_LOGGROUP_QUEUE_SIZE 32

#define CLS_MAX_MANAGER_FLUSH_COUNT 100 // 10MS * 100
#define CLS_MAX_SENDER_FLUSH_COUNT 100  // 10ms * 100

#ifdef WIN32
DWORD WINAPI ClsSendThread(LPVOID param);
#else
void *ClsSendThread(void *param);
#endif

void _generate_cls_pack_id_timestamp(long *timestamp)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    *(timestamp) = ts.tv_nsec;
}

char *_get_cls_pack_id(const char *configName, const char *ip)
{
    long timestamp;
    _generate_cls_pack_id_timestamp(&timestamp);

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

void _try_flush_cls_loggroup(ClsProducerManager *producermgr)
{
    int32_t now_time = time(NULL);

    pthread_mutex_lock(producermgr->lock);
    if (producermgr->builder != NULL && now_time - producermgr->firstLogTime > producermgr->producerconf->packageTimeoutInMS / 1000)
    {
        cls_log_group_builder *builder = producermgr->builder;
        cls_log_recovery_manager *persistent_manager = (cls_log_recovery_manager *)producermgr->uuid_user_param;
        if(persistent_manager != NULL){
            pthread_mutex_lock(persistent_manager->lock);
            int rst = log_recovery_manager_save_cls_log(persistent_manager, builder);
            if (rst != CLS_LOG_PRODUCER_OK)
            {
                cls_log_group_destroy(builder);
                pthread_mutex_unlock(persistent_manager->lock);
                pthread_mutex_lock(producermgr->lock);
                return;
            }
            
            builder->end_uuid = builder->start_uuid= persistent_manager->checkpoint.now_log_uuid - 1;
            pthread_mutex_unlock(persistent_manager->lock);
        }
        
        producermgr->builder = NULL;
        pthread_mutex_unlock(producermgr->lock);

        size_t loggroup_size = builder->loggroup_size;
        int rst = cls_log_queue_push(producermgr->loggroup_queue, builder);
        cls_debug_log("try push loggroup to flusher, size : %d, status : %d", (int)loggroup_size, rst);
        if (rst != 0)
        {
            cls_error_log("try push loggroup to flusher failed, force drop this log group, error code : %d", rst);
            if (producermgr->callbackfunc != NULL)
            {
                producermgr->callbackfunc(producermgr->producerconf->topic, CLS_LOG_PRODUCER_DROP_ERROR, loggroup_size, 0,
                                                     NULL, "try push loggroup to flusher failed, force drop this log group", NULL, producermgr->user_param);
            }
            cls_log_group_destroy(builder);
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
DWORD WINAPI cls_log_producer_flush_thread(LPVOID param)
#else
void *cls_log_producer_flush_thread(void *param)
#endif
{
    ClsProducerManager *root_producer_manager = (ClsProducerManager *)param;
    cls_info_log("start run flusher thread, topic : %s", root_producer_manager->producerconf->topic);
    while (root_producer_manager->shutdown == 0)
    {

        pthread_mutex_lock(root_producer_manager->lock);
        COND_CLS_WAIT_TIME(root_producer_manager->triger_cond,
                       root_producer_manager->lock,
                       CLS_LOG_PRODUCER_FLUSH_INTERVAL_MS);
        pthread_mutex_unlock(root_producer_manager->lock);
        do
        {
            // if send queue is full, skip pack and send data
            if (root_producer_manager->send_param_queue_write - root_producer_manager->send_param_queue_read >= root_producer_manager->send_param_queue_size)
            {
                break;
            }
            void *data = cls_log_queue_trypop(root_producer_manager->loggroup_queue);
            if (data != NULL)
            {
                // process data
                cls_log_group_builder *builder = (cls_log_group_builder *)data;

                ClsProducerManager *producermgr = (ClsProducerManager *)builder->private_value;
                pthread_mutex_lock(root_producer_manager->lock);
                producermgr->totalBufferSize -= builder->loggroup_size;
                pthread_mutex_unlock(root_producer_manager->lock);

                ClsProducerConfig *config = producermgr->producerconf;
                if (config->topic != NULL)
                {
                    AddClsTopic(builder, config->topic, strlen(config->topic));
                }
                if (config->source != NULL)
                {
                    AddClsSource(builder, producermgr->source, strlen(producermgr->source));
                }
                if (producermgr->pack_prefix != NULL)
                {
                    AddClsPackageId(builder, producermgr->pack_prefix, strlen(producermgr->pack_prefix), producermgr->pack_index++);
                }

                cls_lz4_content *lz4_buf = NULL;
                // check compress type
                if (config->compressType == 1)
                {
                    lz4_buf = ClsSerializeWithlz4(builder);
                }
                else
                {
                    lz4_buf = ClsSerializeWithNolz4(builder);
                }

                if (lz4_buf == NULL)
                {
                    cls_error_log("serialize loggroup to proto buf with lz4 failed");
                    if (producermgr->callbackfunc)
                    {
                        producermgr->callbackfunc(producermgr->producerconf->topic, CLS_LOG_PRODUCER_DROP_ERROR, builder->loggroup_size, 0,
                                                             NULL, "serialize loggroup to proto buf with lz4 failed", NULL, producermgr->user_param);
                    }
                    if (producermgr->send_done_persistent_function != NULL)
                    {
                        producermgr->send_done_persistent_function(producermgr->producerconf->topic,
                                                                  CLS_LOG_PRODUCER_INVALID,
                                                                  builder->loggroup_size,
                                                                  0,
                                                                  NULL,
                                                                  "invalid send param, magic num not found",
                                                                  NULL,
                                                                  producermgr->uuid_user_param,
                                                                  builder->start_uuid,
                                                                  builder->end_uuid);
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
                    cls_log_producer_send_param *send_param = ConstructClsSendParam(config, producermgr, lz4_buf, builder);
                    root_producer_manager->send_param_queue[root_producer_manager->send_param_queue_write++ % root_producer_manager->send_param_queue_size] = send_param;
                }
                cls_log_group_destroy(builder);
                continue;
            }
            break;
        } while (1);

        _try_flush_cls_loggroup(root_producer_manager);

        // send data
        if (root_producer_manager->send_threads != NULL)
        {
            // if send thread count > 0, we just push send_param to sender queue
            while (root_producer_manager->send_param_queue_write > root_producer_manager->send_param_queue_read && !CheckClsLogQueueIsFull(root_producer_manager->send_queue))
            {
                cls_log_producer_send_param *send_param = root_producer_manager->send_param_queue[root_producer_manager->send_param_queue_read++ % root_producer_manager->send_param_queue_size];
                // push always success
                cls_log_queue_push(root_producer_manager->send_queue, send_param);
            }
        }
        else if (root_producer_manager->send_param_queue_write > root_producer_manager->send_param_queue_read)
        {
            // if no sender thread, we send this packet out in flush thread
            cls_log_producer_send_param *send_param = root_producer_manager->send_param_queue[root_producer_manager->send_param_queue_read++ % root_producer_manager->send_param_queue_size];
            SendClsData(send_param);
        }
    }
    cls_info_log("exit flusher thread, topic : %s", root_producer_manager->producerconf->topic);
    return 0;
}

ClsProducerManager *ConstructorClsProducerManager(ClsProducerConfig *producerconf)
{
    cls_debug_log("create log producer manager : %s", producerconf->topic);
    ClsProducerManager *producermgr = (ClsProducerManager *)malloc(sizeof(ClsProducerManager));
    memset(producermgr, 0, sizeof(ClsProducerManager));

    producermgr->producerconf = producerconf;

    int64_t base_queue_size = producerconf->maxBufferBytes / (producerconf->logBytesPerPackage + 1) + 10;
    if (base_queue_size < CLS_MIN_LOGGROUP_QUEUE_SIZE)
    {
        base_queue_size = CLS_MIN_LOGGROUP_QUEUE_SIZE;
    }
    else if (base_queue_size > CLS_MAX_LOGGROUP_QUEUE_SIZE)
    {
        base_queue_size = CLS_MAX_LOGGROUP_QUEUE_SIZE;
    }

    producermgr->loggroup_queue = ConstructClsLogQueue(base_queue_size);
    producermgr->send_param_queue_size = base_queue_size * 2;
    producermgr->send_param_queue = malloc(sizeof(cls_log_producer_send_param *) * producermgr->send_param_queue_size);

    if (producerconf->sendThreadCount > 0)
    {
        producermgr->send_thread_count = 0;
        producermgr->send_threads = (pthread_t *)malloc(sizeof(pthread_t) * producerconf->sendThreadCount);
        producermgr->send_queue = ConstructClsLogQueue(base_queue_size * 2);
        int32_t threadId = 0;
        for (; threadId < producermgr->producerconf->sendThreadCount; ++threadId)
        {
            CLS_THREAD_INIT(producermgr->send_threads[threadId], ClsSendThread, producermgr);
        }
    }

    producermgr->triger_cond = InitClsCond();
    producermgr->lock = InitClsMutex();
    CLS_THREAD_INIT(producermgr->flush_thread, cls_log_producer_flush_thread, producermgr);
    if (producerconf->source != NULL)
    {
        producermgr->source = cls_sdsnew(producerconf->source);
    }
    else
    {
        producermgr->source = cls_sdsnew("undefined");
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

void _push_last_cls_loggroup(ClsProducerManager *manager)
{
    pthread_mutex_lock(manager->lock);
    cls_log_group_builder *builder = manager->builder;
    manager->builder = NULL;
    if (builder != NULL)
    {
        size_t loggroup_size = builder->loggroup_size;
        cls_debug_log("try push loggroup to flusher, size : %d, log size %d", (int)builder->loggroup_size, (int)builder->grp->logs.now_buffer_len);
        cls_log_recovery_manager *persistent_manager = (cls_log_recovery_manager *)manager->uuid_user_param;
        if(persistent_manager != NULL){
            pthread_mutex_lock(persistent_manager->lock);
            int rst = log_recovery_manager_save_cls_log(persistent_manager, builder);
            if (rst != CLS_LOG_PRODUCER_OK)
            {
                cls_log_group_destroy(builder);
                pthread_mutex_unlock(persistent_manager->lock);
                pthread_mutex_lock(manager->lock);
                return;
            }
            
            builder->end_uuid = builder->start_uuid= persistent_manager->checkpoint.now_log_uuid - 1;
            pthread_mutex_unlock(persistent_manager->lock);
        }
        int32_t status = cls_log_queue_push(manager->loggroup_queue, builder);
        if (status != 0)
        {
            cls_error_log("try push loggroup to flusher failed, force drop this log group, error code : %d", status);
            cls_log_group_destroy(builder);
        }
        else
        {
            manager->totalBufferSize += loggroup_size;
            pthread_cond_signal(manager->triger_cond);
        }
    }
    pthread_mutex_unlock(manager->lock);
}

void destroy_cls_log_producer_manager(ClsProducerManager *manager)
{
    // when destroy instance, flush last loggroup
    _push_last_cls_loggroup(manager);

    cls_info_log("flush out producer loggroup begin");
    int32_t total_wait_count = manager->producerconf->destroyFlusherWaitTimeoutSec > 0 ? manager->producerconf->destroyFlusherWaitTimeoutSec * 100 : CLS_MAX_MANAGER_FLUSH_COUNT;
    total_wait_count += manager->producerconf->destroySenderWaitTimeoutSec > 0 ? manager->producerconf->destroySenderWaitTimeoutSec * 100 : CLS_MAX_SENDER_FLUSH_COUNT;

#ifdef WIN32
    Sleep(10);
#else
    usleep(10 * 1000);
#endif

    int waitCount = 0;
    while (GetClsLogQueueSize(manager->loggroup_queue) > 0 ||
           manager->send_param_queue_write - manager->send_param_queue_read > 0 ||
           (manager->send_queue != NULL && GetClsLogQueueSize(manager->send_queue) > 0))
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
        cls_error_log("try flush out producer loggroup error, force exit, now loggroup %d", (int)(GetClsLogQueueSize(manager->loggroup_queue)));
    }
    else
    {
        cls_info_log("flush out producer loggroup success");
    }
    manager->shutdown = 1;

    // destroy root resources
    pthread_cond_signal(manager->triger_cond);
    cls_info_log("join flush thread begin");
    CLS_THREAD_JOIN(manager->flush_thread);
    cls_info_log("join flush thread success");
    if (manager->send_threads != NULL)
    {
        cls_info_log("join sender thread pool begin");
        int32_t threadId = 0;
        for (; threadId < manager->producerconf->sendThreadCount; ++threadId)
        {
            CLS_THREAD_JOIN(manager->send_threads[threadId]);
        }
        free(manager->send_threads);
        cls_info_log("join sender thread pool success");
    }
    DeleteClsCond(manager->triger_cond);
    DestroyClsLogQueue(manager->loggroup_queue);
    if (manager->send_queue != NULL)
    {
        cls_info_log("flush out sender queue begin");
        while (GetClsLogQueueSize(manager->send_queue) > 0)
        {
            void *send_param = cls_log_queue_trypop(manager->send_queue);
            if (send_param != NULL)
            {
                SendClsProcess(send_param);
            }
        }
        DestroyClsLogQueue(manager->send_queue);
        cls_info_log("flush out sender queue success");
    }
    DestroyClsMutex(manager->lock);
    if (manager->pack_prefix != NULL)
    {
        free(manager->pack_prefix);
    }
    if (manager->send_param_queue != NULL)
    {
        free(manager->send_param_queue);
    }
    cls_sdsfree(manager->source);
    free(manager);
}

#define CLS_LOG_PRODUCER_MANAGER_ADD_LOG_BEGIN                                                     \
    if (producermgr->totalBufferSize > producermgr->producerconf->maxBufferBytes) \
    {                                                                                          \
        return CLS_LOG_PRODUCER_DROP_ERROR;                                                        \
    }                                                                                          \
    pthread_mutex_lock(producermgr->lock);                                                          \
    if (producermgr->builder == NULL)                                                     \
    {                                                                                          \
        if (CheckClsLogQueueIsFull(producermgr->loggroup_queue))                                \
        {                                                                                      \
            pthread_mutex_unlock(producermgr->lock);                                                  \
            return CLS_LOG_PRODUCER_DROP_ERROR;                                                    \
        }                                                                                      \
        int32_t now_time = time(NULL);                                                         \
        producermgr->builder = GenerateClsLogGroup();                                        \
        producermgr->builder->start_uuid = uuid;                                       \
        producermgr->firstLogTime = now_time;                                             \
        producermgr->builder->private_value = producermgr;                           \
    }

#define CLS_LOG_PRODUCER_MANAGER_ADD_LOG_END                                                                                                                                                                                                                                                                                             \
cls_log_group_builder *builder = producermgr->builder;                                                                          builder->end_uuid = uuid;                                                                                                                                                                                                \
    int32_t nowTime = time(NULL);                                                                                                                                                                                                                                                                                                    \
    if (flush == 0 && producermgr->builder->loggroup_size < producermgr->producerconf->logBytesPerPackage && nowTime - producermgr->firstLogTime < producermgr->producerconf->packageTimeoutInMS / 1000 && producermgr->builder->grp->logs_count < producermgr->producerconf->logCountPerPackage) \
    {                                                                                                                                                                                                                                                                                                                                \
        pthread_mutex_unlock(producermgr->lock);                                                                                                                                                                                                                                                                                            \
        return CLS_LOG_PRODUCER_OK;                                                                                                                                                                                                                                                                                                      \
    }                                                                                                                                                                                                                                                                                                                                \
    int ret = CLS_LOG_PRODUCER_OK;                                                                                                                                                                                                                                                                                                       \
    producermgr->builder = NULL;                                                                                                                                                                                                                                                                                                \
    size_t loggroup_size = builder->loggroup_size;                                                                                                                                                                                                                                                                                   \
    cls_debug_log("try push loggroup to flusher, size : %d, log count %d", (int)builder->loggroup_size, (int)builder->grp->logs_count);                                                                                                                                                                                                  \
    int status = cls_log_queue_push(producermgr->loggroup_queue, builder);                                                                                                                                                                                                                                                          \
    if (status != 0)                                                                                                                                                                                                                                                                                                                 \
    {                                                                                                                                                                                                                                                                                                                                \
        cls_error_log("try push loggroup to flusher failed, force drop this log group, error code : %d", status);                                                                                                                                                                                                                    \
        ret = CLS_LOG_PRODUCER_DROP_ERROR;                                                                                                                                                                                                                                                                                               \
        cls_log_group_destroy(builder);                                                                                                                                                                                                                                                                                                  \
    }                                                                                                                                                                                                                                                                                                                                \
    else                                                                                                                                                                                                                                                                                                                             \
    {                                                                                                                                                                                                                                                                                                                                \
        producermgr->totalBufferSize += loggroup_size;                                                                                                                                                                                                                                                                          \
        pthread_cond_signal(producermgr->triger_cond);                                                                                                                                                                                                                                                                                  \
    }                                                                                                                                                                                                                                                                                                                                \
    pthread_mutex_unlock(producermgr->lock);                                                                                                                                                                                                                                                                                                \
    return ret;

int
cls_log_producer_manager_add_log(ClsProducerManager *producermgr,
                                   int64_t logtime,
                                   int32_t pair_count, char **keys,
                                   int32_t *key_lens, char **values,
                                   int32_t *val_lens, int flush, int64_t uuid)
{
    CLS_LOG_PRODUCER_MANAGER_ADD_LOG_BEGIN;

    InnerAddClsLog(producermgr->builder, logtime, pair_count, keys, key_lens, values, val_lens);

    CLS_LOG_PRODUCER_MANAGER_ADD_LOG_END;
}

int
log_producer_manager_add_log_raw(ClsProducerManager *producermgr,
                                 char *logBuf, size_t logSize, int flush,
                                 int64_t uuid,int* len_index,int64_t logs_count)
{
    if (producermgr->totalBufferSize > producermgr->producerconf->maxBufferBytes)
    {
        return CLS_LOG_PRODUCER_DROP_ERROR;
    }
    pthread_mutex_lock(producermgr->lock);
    if (producermgr->builder == NULL)
    {
        if (CheckClsLogQueueIsFull(producermgr->loggroup_queue))
        {
            pthread_mutex_unlock(producermgr->lock);
            return CLS_LOG_PRODUCER_DROP_ERROR;
        }
        int32_t now_time = time(NULL);
        producermgr->builder = GenerateClsLogGroup();
        producermgr->builder->start_uuid = uuid;
        producermgr->firstLogTime = now_time;
        producermgr->builder->private_value = producermgr;
    }
    
    add_cls_log_raw(producermgr->builder,logBuf,logSize,len_index,logs_count);
    
    cls_log_group_builder *builder = producermgr->builder;
    builder->end_uuid = uuid;
    int32_t nowTime = time(NULL);
    int ret = CLS_LOG_PRODUCER_OK;
    producermgr->builder = NULL;
    size_t loggroup_size = builder->loggroup_size;
    cls_debug_log("try push loggroup to flusher, size : %d, log count %d", (int)builder->loggroup_size, (int)builder->grp->logs_count);
    int status = cls_log_queue_push(producermgr->loggroup_queue, builder);
    if (status != 0)
    {
        cls_error_log("try push loggroup to flusher failed, force drop this log group, error code : %d", status);
        ret = CLS_LOG_PRODUCER_DROP_ERROR;
        cls_log_group_destroy(builder);
    }
    else
    {
        producermgr->totalBufferSize += loggroup_size;
        pthread_cond_signal(producermgr->triger_cond);
    }
    pthread_mutex_unlock(producermgr->lock);
    return ret;
    
    return 0;

}
