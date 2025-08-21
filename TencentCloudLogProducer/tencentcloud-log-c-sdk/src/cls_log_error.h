//
// Created by herrylv on 06/5/2022.
//

#ifndef CLS_LOG_C_SDK_LOG_ERROR_H
#define CLS_LOG_C_SDK_LOG_ERROR_H

#include "cls_log_define.h"
#include <stddef.h>
#include <stdint.h>

typedef void (*ClsSendCallBackFunc)(
    const char *config_name, int result, size_t log_bytes,
    size_t compressed_bytes, const char *req_id, const char *error_message,
    const unsigned char *raw_buffer, void *user_param);

typedef void(*on_cls_log_producer_send_done_function)(const char * config_name,
        int result,
        size_t log_bytes,
        size_t compressed_bytes,
        const char * req_id,
        const char * error_message,
        const unsigned char * raw_buffer,
        void *user_param,
        int64_t startId,
        int64_t endId);


extern int CLS_LOG_PRODUCER_OK;
extern int CLS_LOG_PRODUCER_INVALID;
extern int CLS_LOG_PRODUCER_WRITE_ERROR;
extern int CLS_LOG_PRODUCER_DROP_ERROR;
extern int CLS_LOG_PRODUCER_SEND_NETWORK_ERROR;
extern int CLS_LOG_PRODUCER_SEND_QUOTA_ERROR;
extern int CLS_LOG_PRODUCER_SEND_UNAUTHORIZED;
extern int CLS_LOG_PRODUCER_SEND_SERVER_ERROR;
extern int CLS_LOG_PRODUCER_SEND_DISCARD_ERROR;
extern int CLS_LOG_PRODUCER_SEND_TIME_ERROR;
extern int CLS_LOG_PRODUCER_SEND_EXIT_BUFFERED;
extern int CLS_LOG_PRODUCER_PARAMETERS_INVALID;
extern int CLS_LOG_PRODUCER_PERSISTENT_ERROR;

int is_cls_log_producer_result_ok(int rst);

#endif // CLS_LOG_C_SDK_LOG_ERROR_H
