#include "cls_log.h"
#include <string.h>
#include <stdio.h>
#include <stdarg.h>

LOG_LEVEL cls_log_level = CLS_LOG_WARN;

static const char * _cls_log_level[] = {
        "NONE",
        "NONE",
        "FATAL",
        "ERROR",
        "WARN",
        "INFO",
        "DEBUG",
        "TRACE",
        "NONE"
};


void cls_log_set_level(LOG_LEVEL level)
{   
    cls_log_level = level;
}


void cls_log_format(int level,
                            const char *file,
                            int line,
                            const char *function,
                            const char *fmt, ...)
{
    va_list args;
    char buffer[1024];

    int len = snprintf(buffer, 1020, "[%s] [%s][%s:%d] ",
                   _cls_log_level[level],
                   file, function, line);
    
    va_start(args, fmt);
    len += vsnprintf(buffer + len, 1020 - len, fmt, args);
    va_end(args);

    while (buffer[len -1] == '\n') len--;
    buffer[len++] = '\n';
    buffer[len] = '\0';

    print_log(level, buffer);
}

