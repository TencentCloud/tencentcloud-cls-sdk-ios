#ifndef CLS_LOG_ADAPTOR_H
#define CLS_LOG_ADAPTOR_H

#include "cls_log_define.h"

CLS_LOG_CPP_START

__attribute__ ((visibility("default")))
void SetClsPostFunc(int (*f)(const char *url,
                                     char **header_array,
                                     int header_count,
                                     const void *data,
                                     int data_len));

__attribute__ ((visibility("default")))
void ClsSetTimeUnixFunc(unsigned int (*f)());

CLS_LOG_CPP_END


#endif //CLS_LOG_ADAPTOR_H
