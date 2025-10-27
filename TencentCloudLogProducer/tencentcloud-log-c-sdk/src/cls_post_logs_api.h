#ifndef CLS_POST_LOGS_API_H
#define CLS_POST_LOGS_API_H

#include "cls_log_polymerization.h"
#include "cls_log_define.h"
#include "cls_sds.h"
#include "cls_signature.h"
CLS_LOG_CPP_START

#ifdef WIN32
#undef interface
#endif // WIN32

struct _cls_log_post_option {
  char *interface;       // net interface to send log, NULL as default
  int connecttimeout;   // connection timeout seconds, 0 as default
  int sockertimeout; // operation timeout seconds, 0 as default
  int compress_type;     // 0 no compress, 1 lz4
};
typedef struct _cls_log_post_option cls_log_post_option;

int cls_log_init(int32_t log_global_flag);
void cls_log_destroy();

void PostClsLogsWithLz4(const char *endpoint,
                                       const char *accesskeyId,
                                       const char *accessKey, const char *topic,
                                       cls_lz4_content *buffer,
                                       const char *token,
                                       cls_log_post_option *option,
                     post_cls_result *rst,char* uuid);

void post_cls_log_result_destroy(post_cls_result *result);
void GetClsQueryString(const root_t parameterList, cls_sds queryString);

void SearchClsLogApi(const char *endpoint,root_t httpHeader,root_t params,get_cls_result *result);
CLS_LOG_CPP_END
#endif
