//
// Created by herrylv on 06/5/2022
//

#include "post_logs_client.h"
#include "post_logs_api.h"
#include "log_producer_manager.h"
#include "cls_log.h"
#include "lz4.h"
#include "sds.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
#ifdef WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

unsigned int LOG_GET_TIME();

const char *LOGE_SERVER_BUSY = "ServerBusy";
const char *LOGE_INTERNAL_SERVER_ERROR = "InternalServerError";
const char *LOGE_UNAUTHORIZED = "Unauthorized";
const char *LOGE_WRITE_QUOTA_EXCEED = "WriteQuotaExceed";
const char *LOGE_SHARD_WRITE_QUOTA_EXCEED = "ShardWriteQuotaExceed";
const char *LOGE_TIME_EXPIRED = "RequestTimeExpired";

#define SEND_SLEEP_INTERVAL_MS 1
#define MAX_NETWORK_ERROR_SLEEP_MS 3000
#define BASE_NETWORK_ERROR_SLEEP_MS 300
#define INVALID_TIME_TRY_INTERVAL 500

#define DROP_FAIL_DATA_TIME_SECOND 86400

// #define SEND_TIME_INVALID_FIX

typedef struct
{
    int32_t last_send_error;
    int32_t last_sleep_ms;
    int32_t retryCount;
} send_error_info;

int32_t AfterProcess(ProducerConfig *config,log_producer_send_param *send_param, post_result *result, send_error_info *error_info);

void *SendThread(void *param)
{
    ProducerManager *producermgr = (ProducerManager *)param;

    if (producermgr->send_queue == NULL)
    {
        return 0;
    }

    while (!producermgr->shutdown)
    {
        // change from 30ms to 1000s, reduce wake up when app switch to back
        void *send_param = log_queue_pop(producermgr->send_queue, 1000);
        if (send_param != NULL)
        {
            ATOMICINT_INC(&producermgr->send_thread_count);
            SendProcess(send_param);
            ATOMICINT_DEC(&producermgr->send_thread_count);
        }
    }

    return 0;
}

void *SendProcess(void *param)
{
    log_producer_send_param *send_param = (log_producer_send_param *)param;
    if (send_param->magic_num != LOG_PRODUCER_SEND_MAGIC_NUM)
    {
        cls_fatal_log("invalid send param, magic num not found, num 0x%x", send_param->magic_num);
        ProducerManager *producermgr = (ProducerManager *)send_param->producermgr;
        if (producermgr && producermgr->callbackfunc != NULL)
        {
            producermgr->callbackfunc(producermgr->producerconf->topic, LOG_PRODUCER_INVALID, send_param->log_buf->raw_length, send_param->log_buf->length,
                                                 NULL, "invalid send param, magic num not found", send_param->log_buf->data, producermgr->user_param);
        }
        return NULL;
    }

    ProducerConfig *config = send_param->producerconf;

    send_error_info error_info;
    memset(&error_info, 0, sizeof(error_info));

    ProducerManager *producermgr = (ProducerManager *)send_param->producermgr;

    do
    {
        if (producermgr->shutdown)
        {
            cls_info_log("send fail but shutdown signal received, force exit");
            if (producermgr->callbackfunc != NULL)
            {
                producermgr->callbackfunc(producermgr->producerconf->topic, LOG_PRODUCER_SEND_EXIT_BUFFERED, send_param->log_buf->raw_length, send_param->log_buf->length,
                                                     NULL, "producer is being destroyed, producer has no time to send this buffer out", send_param->log_buf->data, producermgr->user_param);
            }
            break;
        }
        lz4_content *send_buf = send_param->log_buf;
#ifdef SEND_TIME_INVALID_FIX
        uint32_t nowTime = LOG_GET_TIME();
        if (nowTime - send_param->create_time > 600 || send_param->create_time - nowTime > 600 || error_info.last_send_error == LOG_SEND_TIME_ERROR)
        {
            _rebuild_time(send_param->log_buf, &send_buf);
            send_param->create_time = nowTime;
        }
#endif
        log_post_option option;
        memset(&option, 0, sizeof(log_post_option));
        option.connecttimeout = config->connectTimeoutSec;
        option.sockertimeout = config->sendTimeoutSec;
        option.compress_type = config->compressType;
        sds accessKeyId = NULL;
        sds accessKey = NULL;
        sds topic = NULL;
        sds token = NULL;
        GetBaseInfo(config, &accessKeyId, &accessKey, &topic,&token);
        post_result *rst = PostLogsWithLz4(config->endpoint, accessKeyId, accessKey, topic, send_buf,token, &option);
        sdsfree(accessKeyId);
        sdsfree(accessKey);
        sdsfree(topic);
        sdsfree(token);
        int32_t sleepMs = AfterProcess(config,send_param, rst, &error_info);
        post_log_result_destroy(rst);

        // tmp buffer, free
        if (send_buf != send_param->log_buf)
        {
            free(send_buf);
        }

        if (sleepMs <= 0)
        {
            break;
        }
        int i = 0;
        for (i = 0; i < sleepMs; i += SEND_SLEEP_INTERVAL_MS)
        {
            usleep(1000);
            if (producermgr->shutdown)
            {
                break;
            }
        }

    } while (1);

    FreeLogBuf(send_param->log_buf);
    free(send_param);

    return NULL;
}

int32_t AfterProcess(ProducerConfig *config,log_producer_send_param *send_param, post_result *result, send_error_info *error_info)
{
    int32_t send_result = ErrorResult(result);
    ProducerManager *producermgr = (ProducerManager *)send_param->producermgr;
    if (producermgr->callbackfunc != NULL)
    {
        int callback_result = send_result == LOG_SEND_OK ? LOG_PRODUCER_OK : (LOG_PRODUCER_SEND_NETWORK_ERROR + send_result - LOG_SEND_NETWORK_ERROR);
        producermgr->callbackfunc(producermgr->producerconf->topic, callback_result, send_param->log_buf->raw_length, send_param->log_buf->length, result->requestID, result->message, send_param->log_buf->data, producermgr->user_param);
    }
    switch (send_result)
    {
    case LOG_SEND_OK:
        break;
    case LOG_SEND_NETWORK_ERROR:
    case LOG_SEND_SERVER_ERROR:
        if (error_info->last_send_error != LOG_SEND_NETWORK_ERROR
            && error_info->last_send_error != LOG_SEND_SERVER_ERROR)
        {
            error_info->last_send_error = LOG_SEND_NETWORK_ERROR;
            error_info->last_sleep_ms = config->baseRetryBackoffMs;
        }
        else
        {
            if (error_info->last_sleep_ms < config->maxRetryBackoffMs)
            {
                error_info->last_sleep_ms = config->baseRetryBackoffMs + pow(2, error_info->retryCount);
            }
            if (error_info->retryCount >= config->retries || error_info->last_sleep_ms >= config->maxRetryBackoffMs)
            {
                break;
            }
        }
        cls_warn_log("send network error,config : %s, buffer len : %d, raw len : %d, code : %d, error msg : %s",
                     send_param->producerconf->topic,
                     (int)send_param->log_buf->length,
                     (int)send_param->log_buf->raw_length,
                     result->statusCode,
                     result->message);
        error_info->retryCount++;
        return error_info->last_sleep_ms;
    default:
        break;
    }

    pthread_mutex_lock(producermgr->lock);
    producermgr->totalBufferSize -= send_param->log_buf->length;
    pthread_mutex_unlock(producermgr->lock);
    if (send_result == LOG_SEND_OK)
    {
        cls_debug_log("send success,topic : %s, buffer len : %d, raw len : %d, total buffer : %d,code : %d, error msg : %s",
                      send_param->producerconf->topic,
                      (int)send_param->log_buf->length,
                      (int)send_param->log_buf->raw_length,
                      (int)producermgr->totalBufferSize,
                      result->statusCode,
                      result->message);
    }
    else
    {
        cls_warn_log("send fail, discard data,topic : %s, buffer len : %d, raw len : %d, total buffer : %d,code : %d, error msg : %s",
                     send_param->producerconf->topic,
                     (int)send_param->log_buf->length,
                     (int)send_param->log_buf->raw_length,
                     (int)producermgr->totalBufferSize,
                     result->statusCode,
                     result->message);
    }

    return 0;
}


int SendData(log_producer_send_param *send_param)
{
    SendProcess(send_param);
    return LOG_PRODUCER_OK;
}

int32_t ErrorResult(post_result *result)
{
    if (result->statusCode / 100 == 2)
    {
        return LOG_SEND_OK;
    }
    if (result->statusCode <= 0)
    {
        return LOG_SEND_NETWORK_ERROR;
    }
    if (result->statusCode == 405)
    {
        return LOG_SEND_PARAMETERS_ERROR;
    }
    if (result->statusCode == 403)
    {
        return LOG_SEND_QUOTA_EXCEED;
    }
    if (result->statusCode == 401 || result->statusCode == 404)
    {
        return LOG_SEND_UNAUTHORIZED;
    }
    if (result->statusCode >= 500 || result->requestID == NULL)
    {
        return LOG_SEND_SERVER_ERROR;
    }
    if (result->message != NULL && strstr(result->message, LOGE_TIME_EXPIRED) != NULL)
    {
        return LOG_SEND_TIME_ERROR;
    }
    return LOG_SEND_DISCARD_ERROR;
}

log_producer_send_param *ConstructSendParam(ProducerConfig *producerconf,
                                                        void *producermgr,
                                                        lz4_content *log_buf,
                                                        log_group_builder *builder)
{
    log_producer_send_param *param = (log_producer_send_param *)malloc(sizeof(log_producer_send_param));
    param->producerconf = producerconf;
    param->producermgr = producermgr;
    param->log_buf = log_buf;
    param->magic_num = LOG_PRODUCER_SEND_MAGIC_NUM;
    if (builder != NULL)
    {
        param->create_time = builder->create_time;
        param->topic = builder->grp->topic;
    }
    else
    {
        param->create_time = time(NULL);
    }
    return param;
}
