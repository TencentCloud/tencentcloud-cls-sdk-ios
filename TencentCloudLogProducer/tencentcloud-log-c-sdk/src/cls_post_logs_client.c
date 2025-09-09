//
// Created by herrylv on 06/5/2022
//

#include "cls_post_logs_client.h"
#include "cls_post_logs_api.h"
#include "cls_log_producer_manager.h"
#include "cls_log.h"
#include "cls_lz4.h"
#include "cls_sds.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "cls_log_error.h"
#ifdef WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

unsigned int CLS_LOG_GET_TIME();

const char *CLS_LOG_SERVER_BUSY = "ServerBusy";
const char *CLS_LOG_INTERNAL_SERVER_ERROR = "InternalServerError";
const char *CLS_LOG_UNAUTHORIZED = "Unauthorized";
const char *CLS_LOG_WRITE_QUOTA_EXCEED = "WriteQuotaExceed";
const char *CLS_LOG_SHARD_WRITE_QUOTA_EXCEED = "ShardWriteQuotaExceed";
const char *CLS_LOG_TIME_EXPIRED = "RequestTimeExpired";

#define CLS_SEND_SLEEP_INTERVAL_MS 1
#define CLS_MAX_NETWORK_ERROR_SLEEP_MS 3000
#define CLS_BASE_NETWORK_ERROR_SLEEP_MS 300
#define CLS_INVALID_TIME_TRY_INTERVAL 500

#define CLS_DROP_FAIL_DATA_TIME_SECOND 86400

// #define SEND_TIME_INVALID_FIX

typedef struct
{
    int32_t last_send_error;
    int32_t last_sleep_ms;
    int32_t retryCount;
} cls_send_error_info;

int32_t AfterClsProcess(ClsProducerConfig *config,cls_log_producer_send_param *send_param, post_cls_result result, cls_send_error_info *error_info);

void *ClsSendThread(void *param)
{
    ClsProducerManager *producermgr = (ClsProducerManager *)param;

    if (producermgr->send_queue == NULL)
    {
        return 0;
    }

    while (!producermgr->shutdown)
    {
        // change from 30ms to 1000s, reduce wake up when app switch to back
        void *send_param = cls_log_queue_pop(producermgr->send_queue, 1000);
        if (send_param != NULL)
        {
            CLS_ATOMICINT_INC(&producermgr->send_thread_count);
            SendClsProcess(send_param);
            CLS_ATOMICINT_DEC(&producermgr->send_thread_count);
        }
    }

    return 0;
}

void *SendClsProcess(void *param)
{
    cls_log_producer_send_param *send_param = (cls_log_producer_send_param *)param;
    if (send_param->magic_num != CLS_LOG_PRODUCER_SEND_MAGIC_NUM)
    {
        cls_fatal_log("invalid send param, magic num not found, num 0x%x", send_param->magic_num);
        ClsProducerManager *producermgr = (ClsProducerManager *)send_param->producermgr;
        if (producermgr && producermgr->callbackfunc != NULL)
        {
            producermgr->callbackfunc(producermgr->producerconf->topic, CLS_LOG_PRODUCER_INVALID, send_param->log_buf->raw_length, send_param->log_buf->length,
                                                 NULL, "invalid send param, magic num not found", send_param->log_buf->data, producermgr->user_param);
        }
        if (producermgr && producermgr->send_done_persistent_function != NULL)
        {
            producermgr->send_done_persistent_function(producermgr->producerconf->topic,
                                                 CLS_LOG_PRODUCER_INVALID,
                                                 send_param->log_buf->raw_length,
                                                 send_param->log_buf->length,
                                                 NULL,
                                                 "invalid send param, magic num not found",
                                                 send_param->log_buf->data,
                                                 producermgr->uuid_user_param,
                                                 1,
                                                 send_param->start_uuid,
                                                 send_param->end_uuid);
        }
        return NULL;
    }

    ClsProducerConfig *config = send_param->producerconf;

    cls_send_error_info error_info;
    memset(&error_info, 0, sizeof(error_info));

    ClsProducerManager *producermgr = (ClsProducerManager *)send_param->producermgr;

    do
    {
        if (producermgr->shutdown)
        {
            cls_info_log("send fail but shutdown signal received, force exit");
            if (producermgr->callbackfunc != NULL)
            {
                producermgr->callbackfunc(producermgr->producerconf->topic, CLS_LOG_PRODUCER_SEND_EXIT_BUFFERED, send_param->log_buf->raw_length, send_param->log_buf->length,
                                                     NULL, "producer is being destroyed, producer has no time to send this buffer out", send_param->log_buf->data, producermgr->user_param);
            }
            break;
        }
        cls_lz4_content *send_buf = send_param->log_buf;
#ifdef SEND_TIME_INVALID_FIX
        uint32_t nowTime = CLS_LOG_GET_TIME();
        if (nowTime - send_param->create_time > 600 || send_param->create_time - nowTime > 600 || error_info.last_send_error == CLS_LOG_SEND_TIME_ERROR)
        {
            _rebuild_time(send_param->log_buf, &send_buf);
            send_param->create_time = nowTime;
        }
#endif
        cls_log_post_option option;
        memset(&option, 0, sizeof(cls_log_post_option));
        option.connecttimeout = config->connectTimeoutSec;
        option.sockertimeout = config->sendTimeoutSec;
        option.compress_type = config->compressType;
        cls_sds accessKeyId = NULL;
        cls_sds accessKey = NULL;
        cls_sds topic = NULL;
        cls_sds token = NULL;
        ClsGetBaseInfo(config, &accessKeyId, &accessKey, &topic,&token);
        post_cls_result rst;
        rst.statusCode = 0;
        rst.message = NULL;
        memset(rst.requestID, 0, 128);
        PostClsLogsWithLz4(config->endpoint, accessKeyId, accessKey, topic, send_buf,token, &option, &rst);
        cls_sdsfree(accessKeyId);
        cls_sdsfree(accessKey);
        cls_sdsfree(topic);
        cls_sdsfree(token);
        int32_t sleepMs = AfterClsProcess(config,send_param, rst, &error_info);
        if (rst.message != NULL){
            free(rst.message);
            rst.message = NULL;
        }
        

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
        for (i = 0; i < sleepMs; i += CLS_SEND_SLEEP_INTERVAL_MS)
        {
            usleep(1000);
            if (producermgr->shutdown)
            {
                break;
            }
        }

    } while (1);

    ClsFreeLogBuf(send_param->log_buf);
    free(send_param);

    return NULL;
}

int32_t AfterClsProcess(ClsProducerConfig *config,cls_log_producer_send_param *send_param, post_cls_result result, cls_send_error_info *error_info)
{
    int32_t send_result = ErrorClsResult(result);
    int forceFlush = 0;
    ClsProducerManager *producermgr = (ClsProducerManager *)send_param->producermgr;
    if (producermgr->callbackfunc != NULL)
    {
        int callback_result = send_result == CLS_LOG_SEND_OK ? CLS_LOG_PRODUCER_OK : (CLS_LOG_PRODUCER_SEND_NETWORK_ERROR + send_result - CLS_LOG_SEND_NETWORK_ERROR);
        producermgr->callbackfunc(producermgr->producerconf->topic, callback_result, send_param->log_buf->raw_length, send_param->log_buf->length, result.requestID, result.message, send_param->log_buf->data, producermgr->user_param);
    }
    if(result.statusCode == CLS_HTTP_INTERNAL_SERVER_ERROR || result.statusCode == CLS_HTTP_TOO_MANY_REQUESTS || result.statusCode == CLS_HTTP_REQUEST_TIMEOUT || result.statusCode == CLS_HTTP_FORBIDDEN || result.statusCode <= 0){
        if(config->retries == -1){
            error_info->last_sleep_ms = config->baseRetryBackoffMs;
        }
        else if (error_info->last_sleep_ms < config->maxRetryBackoffMs && error_info->retryCount < config->retries)
        {
            error_info->last_sleep_ms = config->baseRetryBackoffMs + pow(2, error_info->retryCount);
            error_info->retryCount++;
        }else{
            forceFlush = 1;
            error_info->last_sleep_ms = 0;
            error_info->retryCount = 0;
        }
    }else{
        forceFlush = 1;
        error_info->last_sleep_ms = 0;
        error_info->retryCount = 0;
    }
    if(forceFlush){
        pthread_mutex_lock(producermgr->lock);
        producermgr->totalBufferSize -= send_param->log_buf->length;
        pthread_mutex_unlock(producermgr->lock);
    }

    if (send_result == CLS_LOG_SEND_OK)
    {
        cls_debug_log("send success,topic : %s, buffer len : %d, raw len : %d, total buffer : %d,code : %d, error msg : %s",
                      send_param->producerconf->topic,
                      (int)send_param->log_buf->length,
                      (int)send_param->log_buf->raw_length,
                      (int)producermgr->totalBufferSize,
                      result.statusCode,
                      result.message);
    }
    else
    {
        cls_warn_log("send fail, discard data,topic : %s, buffer len : %d, raw len : %d, total buffer : %d,code : %d, error msg : %s",
                     send_param->producerconf->topic,
                     (int)send_param->log_buf->length,
                     (int)send_param->log_buf->raw_length,
                     (int)producermgr->totalBufferSize,
                     result.statusCode,
                     result.message);
    }
    
    if (producermgr->send_done_persistent_function != NULL)
    {
        producermgr->send_done_persistent_function(producermgr->producerconf->topic,
                                                  result.statusCode,
                                                  send_param->log_buf->raw_length,
                                                  send_param->log_buf->length,
                                                  result.requestID,
                                                  result.message,
                                                  send_param->log_buf->data,
                                                  producermgr->uuid_user_param,
                                                  forceFlush,
                                                  send_param->start_uuid,
                                                  send_param->end_uuid);
    }

    return error_info->last_sleep_ms;
}


int SendClsData(cls_log_producer_send_param *send_param)
{
    SendClsProcess(send_param);
    return CLS_LOG_PRODUCER_OK;
}

int32_t ErrorClsResult(post_cls_result result)
{
    if (result.statusCode / 100 == 2)
    {
        return CLS_LOG_SEND_OK;
    }
    if (result.statusCode <= 0)
    {
        return CLS_LOG_SEND_NETWORK_ERROR;
    }
    if (result.statusCode == 405)
    {
        return CLS_LOG_SEND_PARAMETERS_ERROR;
    }
    if (result.statusCode == 403)
    {
        return CLS_LOG_SEND_QUOTA_EXCEED;
    }
    if (result.statusCode == 401 || result.statusCode == 404)
    {
        return CLS_LOG_SEND_UNAUTHORIZED;
    }
    if (result.statusCode >= 500 || strlen(result.requestID) == 0)
    {
        return CLS_LOG_SEND_SERVER_ERROR;
    }
    if (result.message != NULL && strstr(result.message, CLS_LOG_TIME_EXPIRED) != NULL)
    {
        return CLS_LOG_SEND_TIME_ERROR;
    }
    return CLS_LOG_SEND_DISCARD_ERROR;
}

cls_log_producer_send_param *ConstructClsSendParam(ClsProducerConfig *producerconf,
                                                        void *producermgr,
                                                        cls_lz4_content *log_buf,
                                                        cls_log_group_builder *builder)
{
    cls_log_producer_send_param *param = (cls_log_producer_send_param *)malloc(sizeof(cls_log_producer_send_param));
    param->producerconf = producerconf;
    param->producermgr = producermgr;
    param->log_buf = log_buf;
    param->magic_num = CLS_LOG_PRODUCER_SEND_MAGIC_NUM;
    if (builder != NULL)
    {
        param->create_time = builder->create_time;
        param->topic = builder->grp->topic;
        param->start_uuid = builder->start_uuid;
        param->end_uuid = builder->end_uuid;
    }
    else
    {
        param->create_time = time(NULL);
        param->start_uuid = builder->start_uuid;
        param->end_uuid = builder->end_uuid;
    }
    return param;
}
