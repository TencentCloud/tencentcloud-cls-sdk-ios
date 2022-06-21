//
// Created by herrylv on 06/5/2022
//

#include "log_producer_config.h"
#include "sds.h"
#include <string.h>
#include <stdlib.h>
#include "cls_log.h"

static void _set_default_producer_config(ProducerConfig *pConfig)
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

static void _copy_config_string(const char *value, sds *src_value)
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
        *src_value = sdsnewEmpty(strLen);
    }
    *src_value = sdscpylen(*src_value, value, strLen);
}

ProducerConfig *ConstructLogConfig()
{
    ProducerConfig *pConfig = (ProducerConfig *)malloc(sizeof(ProducerConfig));
    memset(pConfig, 0, sizeof(ProducerConfig));
    _set_default_producer_config(pConfig);
    return pConfig;
}

void DestroyClsLogProducerConfig(ProducerConfig *pConfig)
{
    if (pConfig->endpoint != NULL)
    {
        sdsfree(pConfig->endpoint);
    }
    if (pConfig->accessKey != NULL)
    {
        sdsfree(pConfig->accessKey);
    }
    if (pConfig->accessKeyId != NULL)
    {
        sdsfree(pConfig->accessKeyId);
    }
    if (pConfig->topic != NULL)
    {
        sdsfree(pConfig->topic);
    }
    if (pConfig->secToken != NULL)
    {
       sdsfree(pConfig->secToken);
    }
    if (pConfig->secTokenLock != NULL)
    {
       pthread_mutex_destroy(pConfig->secTokenLock);
       free(pConfig->secTokenLock);
    }
    if (pConfig->source != NULL)
    {
        sdsfree(pConfig->source);
    }
    free(pConfig);
}

#ifdef LOG_PRODUCER_DEBUG
void ConfigPrint(ProducerConfig *pConfig, FILE *file)
{
    fprintf(file, "endpoint : %s\n", pConfig->endpoint);
    fprintf(file, "accessKeyId : %s\n", pConfig->accessKeyId);
    fprintf(file, "accessKey : %s\n", pConfig->accessKey);
    fprintf(file, "configName : %s\n", pConfig->configName);
    fprintf(file, "topic : %s\n", pConfig->topic);
    fprintf(file, "logLevel : %d\n", pConfig->logLevel);

    fprintf(file, "packageTimeoutInMS : %d\n", pConfig->packageTimeoutInMS);
    fprintf(file, "logCountPerPackage : %d\n", pConfig->logCountPerPackage);
    fprintf(file, "logBytesPerPackage : %d\n", pConfig->logBytesPerPackage);
    fprintf(file, "maxBufferBytes : %d\n", pConfig->maxBufferBytes);
}
#endif

void setPackageTimeout(ProducerConfig *config, int32_t time_out_ms)
{
    if (config == NULL || time_out_ms < 0)
    {
        return;
    }
    config->packageTimeoutInMS = time_out_ms;
}
void SetLogCountLimit(ProducerConfig *config, int32_t log_count)
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
void SetPackageLogBytes(ProducerConfig *config, int32_t log_bytes)
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
void SetMaxBufferLimit(ProducerConfig *config, int64_t max_buffer_bytes)
{
    if (config == NULL || max_buffer_bytes < 0)
    {
        return;
    }
    config->maxBufferBytes = max_buffer_bytes;
}

void set_send_thread_count(ProducerConfig *config, int32_t thread_count)
{
    if (config == NULL || thread_count < 0)
    {
        return;
    }
    config->sendThreadCount = thread_count;
}

void SetConnectTtimeoutSec(ProducerConfig *config, int32_t connect_timeout_sec)
{
    if (config == NULL || connect_timeout_sec <= 0)
    {
        return;
    }
    config->connectTimeoutSec = connect_timeout_sec;
}

void SetSendTimeoutSec(ProducerConfig *config, int32_t send_timeout_sec)
{
    if (config == NULL || send_timeout_sec <= 0)
    {
        return;
    }
    config->sendTimeoutSec = send_timeout_sec;
}

void SetRetries(ProducerConfig *config, int32_t retries)
{
    if (config == NULL || retries <= 0)
    {
        return;
    }
    config->retries = retries;
}

void SetBaseRetryBackoffMs(ProducerConfig *config, int32_t base_retry_backoffMs)
{
    if (config == NULL || base_retry_backoffMs <= 0)
    {
        return;
    }
    config->baseRetryBackoffMs = base_retry_backoffMs;
}

void SetMaxRetryBackoffMs(ProducerConfig *config, int32_t max_retry_backoffMs)
{
    if (config == NULL || max_retry_backoffMs <= 0)
    {
        return;
    }
    config->maxRetryBackoffMs = max_retry_backoffMs;
}

void SetDestroyFlusherWaitSec(ProducerConfig *config, int32_t destroy_flusher_wait_sec)
{
    if (config == NULL || destroy_flusher_wait_sec <= 0)
    {
        return;
    }
    config->destroyFlusherWaitTimeoutSec = destroy_flusher_wait_sec;
}

void SetDestroySenderWaitSec(ProducerConfig *config, int32_t destroy_sender_wait_sec)
{
    if (config == NULL || destroy_sender_wait_sec <= 0)
    {
        return;
    }
    config->destroySenderWaitTimeoutSec = destroy_sender_wait_sec;
}

void SetCompressType(ProducerConfig *config, int32_t compress_type)
{
    if (config == NULL || compress_type < 0 || compress_type > 1)
    {
        return;
    }
    config->compressType = compress_type;
}

void SetEndpoint(ProducerConfig *config, const char *endpoint)
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

void SetAccessId(ProducerConfig *config, const char *access_id)
{
    _copy_config_string(access_id, &config->accessKeyId);
}



void SetAccessKey(ProducerConfig *config, const char *access_key)
{
    _copy_config_string(access_key, &config->accessKey);
}

void resetSecurityToken(ProducerConfig * config, const char * security_token){
    if (config->secTokenLock == NULL)
    {
        config->secTokenLock = InitMutex();
    }
    pthread_mutex_lock(config->secTokenLock);
    _copy_config_string(security_token, &config->secToken);
    pthread_mutex_unlock(config->secTokenLock);
}

void GetBaseInfo(ProducerConfig *config, char **access_id, char **access_secret, char **topic,char **sec_token)
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

void SetTopic(ProducerConfig *config, const char *topic)
{
    _copy_config_string(topic, &config->topic);
}

void SetSource(ProducerConfig *config, const char *source)
{
    _copy_config_string(source, &config->source);
}

int is_valid(ProducerConfig *config)
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
    return 1;
}
