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
int CLS_LOG_PRODUCER_PERSISTENT_ENOUGH = 98;
int CLS_LOG_PRODUCER_PERSISTENT_ERROR = 99;

/*服务端的状态码*/
int CLS_HTTP_SUCCESS = 200;                      // 成功
int CLS_HTTP_BAD_REQUEST = 400;                  // 参数无效
int CLS_HTTP_UNAUTHORIZED = 401;                 // 鉴权失败
int CLS_HTTP_FORBIDDEN = 403;                    // 拉黑｜content|tag超过限制
int CLS_HTTP_NOT_FOUND = 404;                    // topic不存在
int CLS_HTTP_REQUEST_TIMEOUT = 408;              // 客户端超时
int CLS_HTTP_CONFLICT = 409;                     // logset冲突
int CLS_HTTP_PAYLOAD_TOO_LARGE = 413;            // content超过限制
int CLS_HTTP_LOCKED = 423;                       // topic状态异常
int CLS_HTTP_TOO_MANY_REQUESTS = 429;            // 限频
int CLS_HTTP_CLIENT_CLOSED_REQUEST = 499;        // 客户端关闭请求
int CLS_HTTP_INTERNAL_SERVER_ERROR = 500;        // 服务端异常
int CLS_HTTP_SERVICE_UNAVAILABLE = 503;          // 服务不可用



int is_cls_log_producer_result_ok(int rst)
{
    return rst == CLS_LOG_PRODUCER_OK;
}

