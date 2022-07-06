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

struct result
{
    int statusCode;
    char * message;
    char * requestID;
};
//内部api使用的错误
typedef struct result post_result;

typedef struct result get_result;


#endif
