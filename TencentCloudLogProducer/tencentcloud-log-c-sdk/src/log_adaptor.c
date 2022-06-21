#include "log_adaptor.h"
#include <string.h>
#include <time.h>

CLS_LOG_CPP_START

__attribute__((visibility("default"))) void SetPostFunc(int (*f)(const char *url,
                                                                            char **header_array,
                                                                            int header_count,
                                                                            const void *data,
                                                                            int data_len));

__attribute__((visibility("default"))) void SetTimeUnixFunc(unsigned int (*f)());

static int (*__LOGPostAdapt)(const char *url,
                                char **header_array,
                                int header_count,
                                const void *data,
                                int data_len) = NULL;

static unsigned int (*__LOG_GET_TIME)() = NULL;

void SetPostFunc(int (*f)(const char *url,
                                     char **header_array,
                                     int header_count,
                                     const void *data,
                                     int data_len))
{
    __LOGPostAdapt = f;
}

void SetTimeUnixFunc(unsigned int (*f)())
{
    __LOG_GET_TIME = f;
}

unsigned int LOG_GET_TIME()
{
    if (__LOG_GET_TIME == NULL)
    {
        return time(NULL);
    }
    return __LOG_GET_TIME();
}

int LOGPostAdapt(const char *url,
                    char **header_array,
                    int header_count,
                    const void *data,
                    int data_len)
{
    int (*f)(const char *url,
             char **header_array,
             int header_count,
             const void *data,
             int data_len) = NULL;
    f = __LOGPostAdapt;
    int ret = 506;
    if (f != NULL)
    {
        ret = f(url, header_array, header_count, data, data_len);
    }
    return ret;
}

CLS_LOG_CPP_END
