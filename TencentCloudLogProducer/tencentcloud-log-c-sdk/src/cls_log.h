#ifndef CLS_LIBAOS_LOG_H
#define CLS_LIBAOS_LOG_H
#include <string.h>

#ifdef __cplusplus
extern "C"
{
#endif

typedef enum {
    DEFAULT = 1,
    CLS_LOG_FATAL,
    CLS_LOG_ERROR,
    CLS_LOG_WARN,
    CLS_LOG_INFO,
    CLS_LOG_DEBUG,
    CLS_LOG_TRACE,
    CLS_LOG_ALL
} LOG_LEVEL;

extern LOG_LEVEL cls_log_level;

void cls_log_format(int level,
                     const char *file,
                     int line,
                     const char *function,
                     const char *fmt, ...);

void cls_log_set_level(LOG_LEVEL level);
#define print_log(level, log) puts(log)
#define __FL_NME__ (strchr(__FILE__, '/') ? strrchr(__FILE__, '/') + 1 : __FILE__)
#define cls_fatal_log(format, args...) if(cls_log_level>=CLS_LOG_FATAL) \
        cls_log_format(CLS_LOG_FATAL, __FL_NME__, __LINE__, __FUNCTION__, format, ## args)
#define cls_error_log(format, args...) if(cls_log_level>=CLS_LOG_ERROR) \
        cls_log_format(CLS_LOG_ERROR, __FL_NME__, __LINE__, __FUNCTION__, format, ## args)
#define cls_warn_log(format, args...) if(cls_log_level>=CLS_LOG_WARN)   \
        cls_log_format(CLS_LOG_WARN, __FL_NME__, __LINE__, __FUNCTION__, format, ## args)
#define cls_info_log(format, args...) if(cls_log_level>=CLS_LOG_INFO)   \
        cls_log_format(CLS_LOG_INFO, __FL_NME__, __LINE__, __FUNCTION__, format, ## args)
#define cls_debug_log(format, args...) if(cls_log_level>=CLS_LOG_DEBUG) \
        cls_log_format(CLS_LOG_DEBUG, __FL_NME__, __LINE__, __FUNCTION__, format, ## args)

#ifdef __cplusplus
}
#endif

#endif
