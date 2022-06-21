#ifndef CLS_HTTP_INTERFACE_H
#define CLS_HTTP_INTERFACE_H

#include "log_define.h"

CLS_LOG_CPP_START

__attribute__ ((visibility("default")))
void SetPostFunc(int (*f)(const char *url,
                                     char **header_array,
                                     int header_count,
                                     const void *data,
                                     int data_len));

__attribute__ ((visibility("default")))
void SetTimeUnixFunc(unsigned int (*f)());

CLS_LOG_CPP_END


#endif
