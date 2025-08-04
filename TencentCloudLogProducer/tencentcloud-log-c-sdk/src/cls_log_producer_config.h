//
// Created by herrylv on 06/5/2022
//

#ifndef CLS_LOG_C_SDK_LOG_PRODUCER_CONFIG_H
#define CLS_LOG_C_SDK_LOG_PRODUCER_CONFIG_H

#include "cls_log_define.h"
#include "cls_log_multi_thread.h"
#include "cls_log_error.h"
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
CLS_LOG_CPP_START

typedef struct _cls_log_producer_config {
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
    

} ClsProducerConfig;

ClsProducerConfig *ClsConstructLogConfig();

 void ClsSetEndpoint(ClsProducerConfig *config,const char *endpoint);

 void ClsSetAccessId(ClsProducerConfig *config,const char *access_id);

 void ClsSetAccessKey(ClsProducerConfig *config,const char *access_id);

 void resetClsSecurityToken(ClsProducerConfig * config,const char * security_token);

void ClsGetBaseInfo(ClsProducerConfig *config,char **access_id,
                  char **access_secret,char **topic,char **sec_token);

 void SetClsTopic(ClsProducerConfig *config,const char *topic);

 void SetClsSource(ClsProducerConfig *config,const char *source);

 void
setClsPackageTimeout(ClsProducerConfig *config,int32_t time_out_ms);

 void
ClsSetLogCountLimit(ClsProducerConfig *config,int32_t log_count);

 void
SetClsPackageLogBytes(ClsProducerConfig *config,int32_t log_bytes);

 void
SetClsMaxBufferLimit(ClsProducerConfig *config,int64_t max_buffer_bytes);

 void
cls_set_send_thread_count(ClsProducerConfig *config,int32_t thread_count);

 void
ClsSetConnectTtimeoutSec(ClsProducerConfig *config,int32_t connect_timeout_sec);

 void
SetClsSendTimeoutSec(ClsProducerConfig *config,int32_t send_timeout_sec);

void
SetClsRetries(ClsProducerConfig *config,int32_t send_timeout_sec);

void
SetClsBaseRetryBackoffMs(ClsProducerConfig *config,int32_t send_timeout_sec);

void
SetClsMaxRetryBackoffMs(ClsProducerConfig *config,int32_t send_timeout_sec);

 void SetClsDestroyFlusherWaitSec(ClsProducerConfig *config, int32_t destroy_flusher_wait_sec);

 void SetClsDestroySenderWaitSec(
                              ClsProducerConfig *config, int32_t destroy_sender_wait_sec);

 void
SetClsCompressType(ClsProducerConfig *config,
                                      int32_t compress_type);

void DestroyClsLogProducerConfig(ClsProducerConfig *config);


 int is_cls_valid(ClsProducerConfig *config);

CLS_LOG_CPP_END

#endif // CLS_LOG_C_SDK_LOG_PRODUCER_CONFIG_H
