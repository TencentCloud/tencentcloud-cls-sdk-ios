//
// Created by herrylv on 06/5/2022
//

#ifndef CLS_LOG_C_SDK_LOG_PRODUCER_SENDER_H
#define CLS_LOG_C_SDK_LOG_PRODUCER_SENDER_H

#include "cls_log_polymerization.h"
#include "cls_log_define.h"
#include "cls_log_producer_config.h"
CLS_LOG_CPP_START

#define CLS_LOG_PRODUCER_SEND_MAGIC_NUM 0x1B35487A

#define CLS_LOG_SEND_OK 0
#define CLS_LOG_SEND_NETWORK_ERROR 1
#define CLS_LOG_SEND_QUOTA_EXCEED 2
#define CLS_LOG_SEND_UNAUTHORIZED 3
#define CLS_LOG_SEND_SERVER_ERROR 4
#define CLS_LOG_SEND_DISCARD_ERROR 5
#define CLS_LOG_SEND_TIME_ERROR 6
#define CLS_LOG_SEND_PARAMETERS_ERROR 8

extern const char *CLS_LOG_SERVER_BUSY;              //= "ServerBusy";
extern const char *CLS_LOG_INTERNAL_SERVER_ERROR;    //= "InternalServerError";
extern const char *CLS_LOG_UNAUTHORIZED;             //= "Unauthorized";
extern const char *CLS_LOG_WRITE_QUOTA_EXCEED;       //="WriteQuotaExceed";
extern const char *CLS_LOG_SHARD_WRITE_QUOTA_EXCEED; //= "ShardWriteQuotaExceed";
extern const char *CLS_LOG_TIME_EXPIRED;             //= "RequestTimeExpired";

typedef struct _cls_log_producer_send_param {
    ClsProducerConfig *producerconf;
  void *producermgr;
  cls_lz4_content *log_buf;
  uint32_t magic_num;
  uint32_t create_time;
  char *topic;
} cls_log_producer_send_param;

extern void *SendClsProcess(void *send_param);

extern int
SendClsData(cls_log_producer_send_param *send_param);

extern int32_t ErrorClsResult(post_cls_result result);

extern cls_log_producer_send_param *
ConstructClsSendParam(ClsProducerConfig *producerconf,
                               void *producermgr, cls_lz4_content *log_buf,
                               cls_log_group_builder *builder);

CLS_LOG_CPP_END

#endif // CLS_LOG_C_SDK_LOG_PRODUCER_SENDER_H
