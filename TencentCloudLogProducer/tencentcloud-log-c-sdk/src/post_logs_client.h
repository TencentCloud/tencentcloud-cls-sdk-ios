//
// Created by herrylv on 06/5/2022
//

#ifndef LOG_C_SDK_LOG_PRODUCER_SENDER_H
#define LOG_C_SDK_LOG_PRODUCER_SENDER_H

#include "log_polymerization.h"
#include "log_define.h"
#include "log_producer_config.h"
CLS_LOG_CPP_START

#define LOG_PRODUCER_SEND_MAGIC_NUM 0x1B35487A

#define LOG_SEND_OK 0
#define LOG_SEND_NETWORK_ERROR 1
#define LOG_SEND_QUOTA_EXCEED 2
#define LOG_SEND_UNAUTHORIZED 3
#define LOG_SEND_SERVER_ERROR 4
#define LOG_SEND_DISCARD_ERROR 5
#define LOG_SEND_TIME_ERROR 6
#define LOG_SEND_PARAMETERS_ERROR 8

extern const char *LOGE_SERVER_BUSY;              //= "ServerBusy";
extern const char *LOGE_INTERNAL_SERVER_ERROR;    //= "InternalServerError";
extern const char *LOGE_UNAUTHORIZED;             //= "Unauthorized";
extern const char *LOGE_WRITE_QUOTA_EXCEED;       //="WriteQuotaExceed";
extern const char *LOGE_SHARD_WRITE_QUOTA_EXCEED; //= "ShardWriteQuotaExceed";
extern const char *LOGE_TIME_EXPIRED;             //= "RequestTimeExpired";

typedef struct _log_producer_send_param {
  ProducerConfig *producerconf;
  void *producermgr;
  lz4_content *log_buf;
  uint32_t magic_num;
  uint32_t create_time;
  char *topic;
} log_producer_send_param;

extern void *SendProcess(void *send_param);

extern int
SendData(log_producer_send_param *send_param);

extern int32_t ErrorResult(post_result result);

extern log_producer_send_param *
ConstructSendParam(ProducerConfig *producerconf,
                               void *producermgr, lz4_content *log_buf,
                               log_group_builder *builder);

CLS_LOG_CPP_END

#endif // LOG_C_SDK_LOG_PRODUCER_SENDER_H
