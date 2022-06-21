#ifndef LIBLOG_API_H
#define LIBLOG_API_H

#include "log_polymerization.h"
#include "log_define.h"
#include "sds.h"
#include "signature.h"
CLS_LOG_CPP_START

#ifdef WIN32
#undef interface
#endif // WIN32

struct _log_post_option {
  char *interface;       // net interface to send log, NULL as default
  int connecttimeout;   // connection timeout seconds, 0 as default
  int sockertimeout; // operation timeout seconds, 0 as default
  int compress_type;     // 0 no compress, 1 lz4
};
typedef struct _log_post_option log_post_option;

int cls_log_init(int32_t log_global_flag);
void cls_log_destroy();

post_result *PostLogsWithLz4(const char *endpoint,
                                       const char *accesskeyId,
                                       const char *accessKey, const char *topic,
                                       lz4_content *buffer,
                                       const char *token,
                                       log_post_option *option);

void post_log_result_destroy(post_result *result);
void GetQueryString(const root_t parameterList, sds queryString);
CLS_LOG_CPP_END
#endif
