//
// Created by herrylv on 06/5/2022.
//

#ifndef LOG_C_SDK_LOG_PRODUCER_COMMON_H_H
#define LOG_C_SDK_LOG_PRODUCER_COMMON_H_H

#include "log_define.h"
#include <stddef.h>
#include <stdint.h>
CLS_LOG_CPP_START

typedef void (*SendCallBackFunc)(
    const char *config_name, int result, size_t log_bytes,
    size_t compressed_bytes, const char *req_id, const char *error_message,
    const unsigned char *raw_buffer, void *user_param);


extern int LOG_PRODUCER_OK;
extern int LOG_PRODUCER_INVALID;
extern int LOG_PRODUCER_WRITE_ERROR;
extern int LOG_PRODUCER_DROP_ERROR;
extern int LOG_PRODUCER_SEND_NETWORK_ERROR;
extern int LOG_PRODUCER_SEND_QUOTA_ERROR;
extern int LOG_PRODUCER_SEND_UNAUTHORIZED;
extern int LOG_PRODUCER_SEND_SERVER_ERROR;
extern int LOG_PRODUCER_SEND_DISCARD_ERROR;
extern int LOG_PRODUCER_SEND_TIME_ERROR;
extern int LOG_PRODUCER_SEND_EXIT_BUFFERED;
extern int LOG_PRODUCER_PARAMETERS_INVALID;

int is_log_producer_result_ok(int rst);

CLS_LOG_CPP_END

#endif // LOG_C_SDK_LOG_PRODUCER_COMMON_H_H
