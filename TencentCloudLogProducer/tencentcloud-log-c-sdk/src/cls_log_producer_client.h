//
// Created by herrylv on 06/5/2022
//

#ifndef CLS_LOG_C_SDK_LOG_PRODUCER_CLIENT_H
#define CLS_LOG_C_SDK_LOG_PRODUCER_CLIENT_H

#include "cls_log_define.h"
#include "cls_log_producer_config.h"
#include "stdbool.h"
CLS_LOG_CPP_START

typedef struct {
  volatile bool efficient;
  void *private_client;
} clslogproducerclient;

typedef struct clslogproducer clslogproducer;

int  ClsLogProducerInit();

void ClsLogProducerDestroy();

clslogproducer *
ConstructorClsLogProducer(ClsProducerConfig *config,
                    ClsSendCallBackFunc callbackfunc,
                    void *user_param);

void DestructorClsLogProducer(clslogproducer *producer);

clslogproducerclient *
GetClsLogProducer(clslogproducer *producer, const char *config_name);

 int PostClsLog(clslogproducerclient *client, int64_t time, int32_t pair_count,
    char **keys, int32_t *key_lens, char **values, int32_t *value_lens,
    int flush);
int
PostClsLogWithPersistent(clslogproducerclient *client,
                                                int64_t logtime,
                                                int32_t pair_count, char **keys,
                                                int32_t *key_lens, char **values,
                         int32_t *value_lens, int flush, int64_t logSize);

/*
 支持search log 能力
 */

int ClsSearchLog(const char *region,const char *secretid, const char* secretkey,const char* logsetid,const char **topicids,const int topicidslens,const char* starttime,const char* endtime,const char* query,size_t limit,const char* context,const char* sort,get_cls_result * result);

int SearchLogCheckParam(const char *region,const char *secretid, const char* secretkey,const char* logsetid,const char **topicids,const int topicidslens,const char* starttime,const char* endtime,const char* query,size_t limit,const char* sort);

//search log init
int ClsLogSearchLogInit();
void ClsLogSearchLogDestroy();
CLS_LOG_CPP_END

#endif // CLS_LOG_C_SDK_LOG_PRODUCER_CLIENT_H
