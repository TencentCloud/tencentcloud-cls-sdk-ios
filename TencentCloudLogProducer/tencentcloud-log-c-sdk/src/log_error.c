//
// Created by herrylv on 06/5/2022.
//

#include "log_error.h"
#ifdef WIN32
#include <windows.h>
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#endif

int LOG_PRODUCER_OK = 0;
int LOG_PRODUCER_INVALID = 1;
int LOG_PRODUCER_WRITE_ERROR = 2;
int LOG_PRODUCER_DROP_ERROR = 3;
int LOG_PRODUCER_SEND_NETWORK_ERROR = 4;
int LOG_PRODUCER_SEND_QUOTA_ERROR = 5;
int LOG_PRODUCER_SEND_UNAUTHORIZED = 6;
int LOG_PRODUCER_SEND_SERVER_ERROR = 7;
int LOG_PRODUCER_SEND_DISCARD_ERROR = 8;
int LOG_PRODUCER_SEND_TIME_ERROR = 9;
int LOG_PRODUCER_SEND_EXIT_BUFFERED = 10;
int LOG_PRODUCER_PARAMETERS_INVALID = 11;

int is_log_producer_result_ok(int rst)
{
    return rst == LOG_PRODUCER_OK;
}

