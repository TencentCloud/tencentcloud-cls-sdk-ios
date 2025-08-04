#ifndef CLS_SDS_H
#define CLS_SDS_H

#define CLS_SDS_MAX_PREALLOC (1024*1024)

#include <sys/types.h>
#include <stdarg.h>

#ifdef WIN32
#define inline __inline
#endif

typedef char *cls_sds;

struct cls_sdshdr {
    unsigned int len;
    unsigned int free;
    char buf[];
};

size_t cls_sdslen(const cls_sds s);

size_t cls_sdsavail(const cls_sds s);

cls_sds cls_sdsnewlen(const void *init, size_t initlen);

cls_sds cls_sdsnewEmpty(size_t preAlloclen);

cls_sds cls_sdsnew(const char *init);

cls_sds cls_sdsempty(void);

size_t cls_sdslen(const cls_sds s);

cls_sds cls_sdsdup(const cls_sds s);

void cls_sdsfree(cls_sds s);

size_t cls_sdsavail(const cls_sds s);

cls_sds cls_sdsgrowzero(cls_sds s, size_t len);

cls_sds cls_sdscatlen(cls_sds s, const void *t, size_t len);

cls_sds cls_sdscat(cls_sds s, const char *t);

cls_sds cls_sdscatchar(cls_sds s, char c);

cls_sds cls_sdscatsds(cls_sds s, const cls_sds t);

cls_sds cls_sdscpylen(cls_sds s, const char *t, size_t len);

cls_sds cls_sdscpy(cls_sds s, const char *t);

cls_sds cls_sdscatvprintf(cls_sds s, const char *fmt, va_list ap);

#ifdef __GNUC__

cls_sds cls_sdscatprintf(cls_sds s, const char *fmt, ...)
__attribute__((format(printf, 2, 3)));

#else
cls_sds cls_sdscatprintf(cls_sds s, const char *fmt, ...);
#endif


#endif
