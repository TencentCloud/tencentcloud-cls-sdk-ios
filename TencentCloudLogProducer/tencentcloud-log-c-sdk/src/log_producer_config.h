//
// Created by herrylv on 06/5/2022
//

#ifndef LOG_C_SDK_LOG_PRODUCER_CONFIG_H
#define LOG_C_SDK_LOG_PRODUCER_CONFIG_H

#include "log_define.h"
#include "log_multi_thread.h"
#include "log_error.h"
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
CLS_LOG_CPP_START

typedef struct _log_producer_config {
  char *endpoint;
  char *accessKeyId;
  char *accessKey;
  char *topic;
  char *secToken;
  char *source;
  pthread_mutex_t* secTokenLock;
  int32_t sendThreadCount;

  int32_t packageTimeoutInMS;
  int32_t logCountPerPackage;
  int32_t logBytesPerPackage;
  int64_t maxBufferBytes;

  int32_t connectTimeoutSec;
  int32_t sendTimeoutSec;
  int32_t destroyFlusherWaitTimeoutSec;
  int32_t destroySenderWaitTimeoutSec;

  int32_t compressType;   // 0 no compress, 1 lz4
    
  int32_t retries;
    
  int32_t baseRetryBackoffMs;
    
  int32_t maxRetryBackoffMs;
    

} ProducerConfig;

 ProducerConfig *ConstructLogConfig();

 void SetEndpoint(ProducerConfig *config,const char *endpoint);

 void SetAccessId(ProducerConfig *config,const char *access_id);

 void SetAccessKey(ProducerConfig *config,const char *access_id);

 void resetSecurityToken(ProducerConfig * config,const char * security_token);

void GetBaseInfo(ProducerConfig *config,char **access_id,
                  char **access_secret,char **topic,char **sec_token);

 void SetTopic(ProducerConfig *config,const char *topic);

 void SetSource(ProducerConfig *config,const char *source);

 void
setPackageTimeout(ProducerConfig *config,int32_t time_out_ms);

 void
SetLogCountLimit(ProducerConfig *config,int32_t log_count);

 void
SetPackageLogBytes(ProducerConfig *config,int32_t log_bytes);

 void
SetMaxBufferLimit(ProducerConfig *config,int64_t max_buffer_bytes);

 void
set_send_thread_count(ProducerConfig *config,int32_t thread_count);

 void
SetConnectTtimeoutSec(ProducerConfig *config,int32_t connect_timeout_sec);

 void
SetSendTimeoutSec(ProducerConfig *config,int32_t send_timeout_sec);

void
SetRetries(ProducerConfig *config,int32_t send_timeout_sec);

void
SetBaseRetryBackoffMs(ProducerConfig *config,int32_t send_timeout_sec);

void
SetMaxRetryBackoffMs(ProducerConfig *config,int32_t send_timeout_sec);

 void SetDestroyFlusherWaitSec(ProducerConfig *config, int32_t destroy_flusher_wait_sec);

 void SetDestroySenderWaitSec(
    ProducerConfig *config, int32_t destroy_sender_wait_sec);

 void
SetCompressType(ProducerConfig *config,
                                      int32_t compress_type);

void DestroyClsLogProducerConfig(ProducerConfig *config);

#ifdef LOG_PRODUCER_DEBUG

void ConfigPrint(ProducerConfig *config, FILE *pFile);

#endif

 int is_valid(ProducerConfig *config);

CLS_LOG_CPP_END

#endif // LOG_C_SDK_LOG_PRODUCER_CONFIG_H
