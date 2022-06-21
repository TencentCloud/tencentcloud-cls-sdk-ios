#ifndef LIBLOG_DEFINE_H
#define LIBLOG_DEFINE_H

#ifdef __cplusplus
# define CLS_LOG_CPP_START extern "C" {
# define CLS_LOG_CPP_END }
#else
# define CLS_LOG_CPP_START
# define CLS_LOG_CPP_END
#endif

#define LOG_GLOBAL_SSL (1<<0)
#define LOG_GLOBAL_WIN32 (1<<1)
#define LOG_GLOBAL_ALL (LOG_GLOBAL_SSL|LOG_GLOBAL_WIN32)
#define LOG_GLOBAL_NOTHING (0)


struct _post_result
{
    int statusCode;
    char * errorMessage;
    char * requestID;
};

typedef struct _post_result post_result;


#endif
