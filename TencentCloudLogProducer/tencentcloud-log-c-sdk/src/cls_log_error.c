//
// Created by herrylv on 06/5/2022.
//

#include "cls_log_error.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>


int CLS_LOG_PRODUCER_OK = 0;
int CLS_LOG_PRODUCER_INVALID = 1;
int CLS_LOG_PRODUCER_WRITE_ERROR = 2;
int CLS_LOG_PRODUCER_DROP_ERROR = 3;
int CLS_LOG_PRODUCER_SEND_NETWORK_ERROR = 4;
int CLS_LOG_PRODUCER_SEND_QUOTA_ERROR = 5;
int CLS_LOG_PRODUCER_SEND_UNAUTHORIZED = 6;
int CLS_LOG_PRODUCER_SEND_SERVER_ERROR = 7;
int CLS_LOG_PRODUCER_SEND_DISCARD_ERROR = 8;
int CLS_LOG_PRODUCER_SEND_TIME_ERROR = 9;
int CLS_LOG_PRODUCER_SEND_EXIT_BUFFERED = 10;
int CLS_LOG_PRODUCER_PARAMETERS_INVALID = 11;
int CLS_LOG_PRODUCER_PERSISTENT_ERROR = 99;

int is_cls_log_producer_result_ok(int rst)
{
    return rst == CLS_LOG_PRODUCER_OK;
}

