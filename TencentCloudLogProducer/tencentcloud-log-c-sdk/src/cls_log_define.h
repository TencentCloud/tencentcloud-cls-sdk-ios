#ifndef LIBCLSLOG_DEFINE_H
#define LIBCLSLOG_DEFINE_H

#ifdef __cplusplus
# define CLS_LOG_CPP_START extern "C" {
# define CLS_LOG_CPP_END }
#else
# define CLS_LOG_CPP_START
# define CLS_LOG_CPP_END
#endif

#define CLS_LOG_GLOBAL_SSL (1<<0)
#define CLS_LOG_GLOBAL_WIN32 (1<<1)
#define CLS_LOG_GLOBAL_ALL (CLS_LOG_GLOBAL_SSL|CLS_LOG_GLOBAL_WIN32)
#define CLS_LOG_GLOBAL_NOTHING (0)

struct cls_result
{
    int statusCode;
    char *message;
    char requestID[128];
};
//内部api使用的错误
typedef struct cls_result post_cls_result;

struct ClsSearchResult{
    int statusCode;
    char *message;
    char requestID[128];
};

typedef struct ClsSearchResult get_cls_result;


#endif
