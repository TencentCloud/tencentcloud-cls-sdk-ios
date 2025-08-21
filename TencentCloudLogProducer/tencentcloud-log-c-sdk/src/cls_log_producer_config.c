//
// Created by herrylv on 06/5/2022
//

#include "cls_log_producer_config.h"
#include "cls_sds.h"
#include <string.h>
#include <stdlib.h>
#include "cls_log.h"

static void _set_default_producer_config(ClsProducerConfig *pConfig)
{
    pConfig->logBytesPerPackage = 1024 * 1024;
    pConfig->logCountPerPackage = 2048;
    pConfig->packageTimeoutInMS = 3000;
    pConfig->maxBufferBytes = 64 * 1024 * 1024;

    pConfig->connectTimeoutSec = 10;
    pConfig->sendTimeoutSec = 15;
    pConfig->destroySenderWaitTimeoutSec = 1;
    pConfig->destroyFlusherWaitTimeoutSec = 1;
    pConfig->compressType = 1;
    
    pConfig->retries = 10;
    pConfig->baseRetryBackoffMs = 100;
    pConfig->maxRetryBackoffMs = 50000;
}

static void _copy_config_string(const char *value, cls_sds *src_value)
{
    if (src_value == NULL)
    {
        return;
    }

    if (value == NULL)
    {
        *src_value = NULL;
        return;
    }

    size_t strLen = strlen(value);
    if (*src_value == NULL)
    {
        *src_value = cls_sdsnewEmpty(strLen);
    }
    *src_value = cls_sdscpylen(*src_value, value, strLen);
}

ClsProducerConfig *ClsConstructLogConfig()
{
    ClsProducerConfig *pConfig = (ClsProducerConfig *)malloc(sizeof(ClsProducerConfig));
    memset(pConfig, 0, sizeof(ClsProducerConfig));
    _set_default_producer_config(pConfig);
    return pConfig;
}

void DestroyClsLogProducerConfig(ClsProducerConfig *pConfig)
{
    if (pConfig->endpoint != NULL)
    {
        cls_sdsfree(pConfig->endpoint);
    }
    if (pConfig->accessKey != NULL)
    {
        cls_sdsfree(pConfig->accessKey);
    }
    if (pConfig->accessKeyId != NULL)
    {
        cls_sdsfree(pConfig->accessKeyId);
    }
    if (pConfig->topic != NULL)
    {
        cls_sdsfree(pConfig->topic);
    }
    if (pConfig->secToken != NULL)
    {
       cls_sdsfree(pConfig->secToken);
    }
    if (pConfig->secTokenLock != NULL)
    {
       pthread_mutex_destroy(pConfig->secTokenLock);
       free(pConfig->secTokenLock);
    }
    if (pConfig->source != NULL)
    {
        cls_sdsfree(pConfig->source);
    }
    if (pConfig->persistentFilePath != NULL)
    {
        cls_sdsfree(pConfig->persistentFilePath);
    }
    free(pConfig);
}

void setClsPackageTimeout(ClsProducerConfig *config, int32_t time_out_ms)
{
    if (config == NULL || time_out_ms < 0)
    {
        return;
    }
    config->packageTimeoutInMS = time_out_ms;
}
void ClsSetLogCountLimit(ClsProducerConfig *config, int32_t log_count)
{
    if (config == NULL || log_count < 0)
    {
        return;
    }
    if(log_count >= 10000){
        config->logCountPerPackage = 9999;
    }else{
        config->logCountPerPackage = log_count;
    }
    
}
void SetClsPackageLogBytes(ClsProducerConfig *config, int32_t log_bytes)
{
    if (config == NULL || log_bytes < 0)
    {
        return;
    }
    if(log_bytes >= 5242880){
        config->logBytesPerPackage = 5242879;
    }else{
        config->logBytesPerPackage = log_bytes;
    }
    
}
void SetClsMaxBufferLimit(ClsProducerConfig *config, int64_t max_buffer_bytes)
{
    if (config == NULL || max_buffer_bytes < 0)
    {
        return;
    }
    config->maxBufferBytes = max_buffer_bytes;
}

void cls_set_send_thread_count(ClsProducerConfig *config, int32_t thread_count)
{
    if (config == NULL || thread_count < 0)
    {
        return;
    }
    config->sendThreadCount = thread_count;
}

void ClsSetConnectTtimeoutSec(ClsProducerConfig *config, int32_t connect_timeout_sec)
{
    if (config == NULL || connect_timeout_sec <= 0)
    {
        return;
    }
    config->connectTimeoutSec = connect_timeout_sec;
}

void SetClsSendTimeoutSec(ClsProducerConfig *config, int32_t send_timeout_sec)
{
    if (config == NULL || send_timeout_sec <= 0)
    {
        return;
    }
    config->sendTimeoutSec = send_timeout_sec;
}

void SetClsRetries(ClsProducerConfig *config, int32_t retries)
{
    if (config == NULL || retries <= 0)
    {
        return;
    }
    config->retries = retries;
}

void SetClsBaseRetryBackoffMs(ClsProducerConfig *config, int32_t base_retry_backoffMs)
{
    if (config == NULL || base_retry_backoffMs <= 0)
    {
        return;
    }
    config->baseRetryBackoffMs = base_retry_backoffMs;
}

void SetClsMaxRetryBackoffMs(ClsProducerConfig *config, int32_t max_retry_backoffMs)
{
    if (config == NULL || max_retry_backoffMs <= 0)
    {
        return;
    }
    config->maxRetryBackoffMs = max_retry_backoffMs;
}

void SetClsDestroyFlusherWaitSec(ClsProducerConfig *config, int32_t destroy_flusher_wait_sec)
{
    if (config == NULL || destroy_flusher_wait_sec <= 0)
    {
        return;
    }
    config->destroyFlusherWaitTimeoutSec = destroy_flusher_wait_sec;
}

void SetClsDestroySenderWaitSec(ClsProducerConfig *config, int32_t destroy_sender_wait_sec)
{
    if (config == NULL || destroy_sender_wait_sec <= 0)
    {
        return;
    }
    config->destroySenderWaitTimeoutSec = destroy_sender_wait_sec;
}

void SetClsCompressType(ClsProducerConfig *config, int32_t compress_type)
{
    if (config == NULL || compress_type < 0 || compress_type > 1)
    {
        return;
    }
    config->compressType = compress_type;
}

void ClsSetEndpoint(ClsProducerConfig *config, const char *endpoint)
{
    if (!endpoint)
    {
        _copy_config_string(NULL, &config->endpoint);
        return;
    }

    if (strlen(endpoint) < 8)
    {
        return;
    }
    if (strncmp(endpoint, "http://", 7) == 0)
    {
        endpoint += 7;
    }
    
    _copy_config_string(endpoint, &config->endpoint);
}

void ClsSetAccessId(ClsProducerConfig *config, const char *access_id)
{
    _copy_config_string(access_id, &config->accessKeyId);
}



void ClsSetAccessKey(ClsProducerConfig *config, const char *access_key)
{
    _copy_config_string(access_key, &config->accessKey);
}

void resetClsSecurityToken(ClsProducerConfig * config, const char * security_token){
    if (config->secTokenLock == NULL)
    {
        config->secTokenLock = InitClsMutex();
    }
    pthread_mutex_lock(config->secTokenLock);
    _copy_config_string(security_token, &config->secToken);
    pthread_mutex_unlock(config->secTokenLock);
}

void ClsGetBaseInfo(ClsProducerConfig *config, char **access_id, char **access_secret, char **topic,char **sec_token)
{
    if(config->secTokenLock == NULL){
        _copy_config_string(config->accessKeyId, access_id);
        _copy_config_string(config->accessKey, access_secret);
        _copy_config_string(config->topic, topic);
    }else{
        pthread_mutex_lock(config->secTokenLock);
        _copy_config_string(config->accessKeyId, access_id);
        _copy_config_string(config->accessKey, access_secret);
        _copy_config_string(config->topic, topic);
        _copy_config_string(config->secToken, sec_token);
        pthread_mutex_unlock(config->secTokenLock);
    }

}

void SetClsTopic(ClsProducerConfig *config, const char *topic)
{
    _copy_config_string(topic, &config->topic);
}

void SetClsSource(ClsProducerConfig *config, const char *source)
{
    _copy_config_string(source, &config->source);
}

int is_cls_valid(ClsProducerConfig *config)
{
    if (config == NULL)
    {
        cls_error_log("invalid producer config");
        return 0;
    }
    if (config->endpoint == NULL)
    {
        cls_error_log("invalid producer config destination params");
        return 0;
    }
    if (config->accessKey == NULL || config->accessKeyId == NULL)
    {
        cls_error_log("invalid producer config authority params");
    }
    if (config->packageTimeoutInMS < 0 || config->maxBufferBytes < 0 || config->logCountPerPackage < 0 || config->logBytesPerPackage < 0)
    {
        cls_error_log("invalid producer config log merge and buffer params");
        return 0;
    }
    if (config->usePersistent)
    {
        if (config->persistentFilePath == NULL || config->maxPersistentFileCount <= 0 || config->maxPersistentLogCount <= 0 || config->maxPersistentFileSize <=0 )
        {
            cls_error_log("invalid producer persistent config params");
            return 0;
        }
    }
    return 1;
}

int log_producer_persistent_config_is_enabled(ClsProducerConfig *config)
{
    if (config == NULL)
    {
        cls_error_log("invalid producer config");
        return 0;
    }
    if (config->usePersistent == 0)
    {
        return 0;
    }
    return 1;
}

void log_producer_config_set_persistent(ClsProducerConfig *config,
                                        int32_t persistent)
{
    if (config == NULL)
        return;
    config->usePersistent = persistent;
}

void log_producer_config_set_persistent_file_path(ClsProducerConfig *config,
                                                  const char *file_path)
{
    if (config == NULL)
        return;
    _copy_config_string(file_path, &config->persistentFilePath);
}

void log_producer_config_set_persistent_max_log_count(ClsProducerConfig *config,
                                           int32_t max_log_count)
{
    if (config == NULL)
        return;
    config->maxPersistentLogCount = max_log_count;
}

void log_producer_config_set_persistent_max_file_size(ClsProducerConfig *config,
                                                 int32_t file_size)
{
    if (config == NULL)
        return;
    config->maxPersistentFileSize = file_size;
}

void log_producer_config_set_persistent_max_file_count(ClsProducerConfig *config,
                                                  int32_t file_count)
{
    if (config == NULL)
        return;
    config->maxPersistentFileCount = file_count;
}

void log_producer_config_set_persistent_force_flush(ClsProducerConfig *config,
                                                    int32_t force)
{
    if (config == NULL)
        return;
    config->forceFlushDisk = force;
}
