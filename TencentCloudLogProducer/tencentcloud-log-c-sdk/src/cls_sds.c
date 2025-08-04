/* SDSLib, A C dynamic strings library
 *
 * Copyright (c) 2006-2012, Salvatore Sanfilippo <antirez at gmail dot com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   * Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *   * Neither the name of Redis nor the names of its contributors may be used
 *     to endorse or promote products derived from this software without
 *     specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <assert.h>
#include "cls_sds.h"

size_t cls_sdslen(const cls_sds s) {
    struct cls_sdshdr *sh = (struct cls_sdshdr *) (s - (sizeof(struct cls_sdshdr)));
    return sh->len;
}

size_t cls_sdsavail(const cls_sds s) {
    struct cls_sdshdr *sh = (struct cls_sdshdr *) (s - (sizeof(struct cls_sdshdr)));
    return sh->free;
}

/* Create a new cls_sds string with the content specified by the 'init' pointer
 * and 'initlen'.
 * If NULL is used for 'init' the string is initialized with zero bytes.
 *
 * The string is always null-termined (all the cls_sds strings are, always) so
 * even if you create an cls_sds string with:
 *
 * mystring = cls_sdsnewlen("abc",3);
 *
 * You can print the string with printf() as there is an implicit \0 at the
 * end of the string. However the string is binary safe and can contain
 * \0 characters in the middle, as the length is stored in the cls_sds header. */
cls_sds cls_sdsnewlen(const void *init, size_t initlen) {
    struct cls_sdshdr *sh;

    if (init) {
        sh = malloc(sizeof(struct cls_sdshdr) + initlen + 1);
    } else {
        sh = calloc(sizeof(struct cls_sdshdr) + initlen + 1, 1);
    }
    if (sh == NULL) return NULL;
    sh->len = initlen;
    sh->free = 0;
    if (initlen && init)
        memcpy(sh->buf, init, initlen);
    sh->buf[initlen] = '\0';
    return (char *) sh->buf;
}


cls_sds cls_sdsnewEmpty(size_t preAlloclen) {
    struct cls_sdshdr *sh;

    sh = malloc(sizeof(struct cls_sdshdr) + preAlloclen + 1);
    if (sh == NULL) return NULL;
    sh->len = 0;
    sh->free = preAlloclen;
    sh->buf[0] = '\0';
    return (char *) sh->buf;
}


/* Create an empty (zero length) cls_sds string. Even in this case the string
 * always has an implicit null term. */
cls_sds cls_sdsempty(void) {
    return cls_sdsnewlen("", 0);
}

/* Create a new cls_sds string starting from a null terminated C string. */
cls_sds cls_sdsnew(const char *init) {
    size_t initlen = (init == NULL) ? 0 : strlen(init);
    return cls_sdsnewlen(init, initlen);
}

/* Duplicate an cls_sds string. */
cls_sds cls_sdsdup(const cls_sds s) {
    if (s == NULL) return NULL;
    return cls_sdsnewlen(s, cls_sdslen(s));
}

/* Free an cls_sds string. No operation is performed if 's' is NULL. */
void cls_sdsfree(cls_sds s) {
    if (s == NULL) return;
    free(s - sizeof(struct cls_sdshdr));
}

/* Set the cls_sds string length to the length as obtained with strlen(), so
 * considering as content only up to the first null term character.
 *
 * This function is useful when the cls_sds string is hacked manually in some
 * way, like in the following example:
 *
 * s = cls_sdsnew("foobar");
 * s[2] = '\0';
 * sdsupdatelen(s);
 * printf("%d\n", cls_sdslen(s));
 *
 * The output will be "2", but if we comment out the call to sdsupdatelen()
 * the output will be "6" as the string was modified but the logical length
 * remains 6 bytes. */
void sdsupdatelen(cls_sds s) {
    struct cls_sdshdr *sh = (void *) (s - (sizeof(struct cls_sdshdr)));
    int reallen = strlen(s);
    sh->free += (sh->len - reallen);
    sh->len = reallen;
}

/* Modify an cls_sds string in-place to make it empty (zero length).
 * However all the existing buffer is not discarded but set as free space
 * so that next append operations will not require allocations up to the
 * number of bytes previously available. */
void sdsclear(cls_sds s) {
    struct cls_sdshdr *sh = (void *) (s - (sizeof(struct cls_sdshdr)));
    sh->free += sh->len;
    sh->len = 0;
    sh->buf[0] = '\0';
}

/* Enlarge the free space at the end of the cls_sds string so that the caller
 * is sure that after calling this function can overwrite up to addlen
 * bytes after the end of the string, plus one more byte for nul term.
 *
 * Note: this does not change the *length* of the cls_sds string as returned
 * by cls_sdslen(), but only the free buffer space we have. */
cls_sds sdsMakeRoomFor(cls_sds s, size_t addlen) {
    struct cls_sdshdr *sh, *newsh;
    size_t free = cls_sdsavail(s);
    size_t len, newlen;

    if (free >= addlen) return s;
    len = cls_sdslen(s);
    sh = (void *) (s - (sizeof(struct cls_sdshdr)));
    newlen = (len + addlen);
    if (newlen < CLS_SDS_MAX_PREALLOC)
        newlen *= 2;
    else
        newlen += CLS_SDS_MAX_PREALLOC;
    newsh = realloc(sh, sizeof(struct cls_sdshdr) + newlen + 1);
    if (newsh == NULL) return NULL;

    newsh->free = newlen - len;
    return newsh->buf;
}

/* Reallocate the cls_sds string so that it has no free space at the end. The
 * contained string remains not altered, but next concatenation operations
 * will require a reallocation.
 *
 * After the call, the passed cls_sds string is no longer valid and all the
 * references must be substituted with the new pointer returned by the call. */
cls_sds sdsRemoveFreeSpace(cls_sds s) {
    struct cls_sdshdr *sh;

    sh = (void *) (s - (sizeof(struct cls_sdshdr)));
    sh = realloc(sh, sizeof(struct cls_sdshdr) + sh->len + 1);
    sh->free = 0;
    return sh->buf;
}

/* Return the total size of the allocation of the specifed cls_sds string,
 * including:
 * 1) The cls_sds header before the pointer.
 * 2) The string.
 * 3) The free buffer at the end if any.
 * 4) The implicit null term.
 */
size_t sdsAllocSize(cls_sds s) {
    struct cls_sdshdr *sh = (void *) (s - (sizeof(struct cls_sdshdr)));

    return sizeof(*sh) + sh->len + sh->free + 1;
}

/* Increment the cls_sds length and decrements the left free space at the
 * end of the string according to 'incr'. Also set the null term
 * in the new end of the string.
 *
 * This function is used in order to fix the string length after the
 * user calls sdsMakeRoomFor(), writes something after the end of
 * the current string, and finally needs to set the new length.
 *
 * Note: it is possible to use a negative increment in order to
 * right-trim the string.
 *
 * Usage example:
 *
 * Using sdsIncrLen() and sdsMakeRoomFor() it is possible to mount the
 * following schema, to cat bytes coming from the kernel to the end of an
 * cls_sds string without copying into an intermediate buffer:
 *
 * oldlen = cls_sdslen(s);
 * s = sdsMakeRoomFor(s, BUFFER_SIZE);
 * nread = read(fd, s+oldlen, BUFFER_SIZE);
 * ... check for nread <= 0 and handle it ...
 * sdsIncrLen(s, nread);
 */
void sdsIncrLen(cls_sds s, int incr) {
    struct cls_sdshdr *sh = (void *) (s - (sizeof(struct cls_sdshdr)));

    if (incr >= 0)
        assert(sh->free >= (unsigned int) incr);
    else
        assert(sh->len >= (unsigned int) (-incr));
    sh->len += incr;
    sh->free -= incr;
    s[sh->len] = '\0';
}

/* Grow the cls_sds to have the specified length. Bytes that were not part of
 * the original length of the cls_sds will be set to zero.
 *
 * if the specified length is smaller than the current length, no operation
 * is performed. */
cls_sds cls_sdsgrowzero(cls_sds s, size_t len) {
    struct cls_sdshdr *sh = (void *) (s - (sizeof(struct cls_sdshdr)));
    size_t totlen, curlen = sh->len;

    if (len <= curlen) return s;
    s = sdsMakeRoomFor(s, len - curlen);
    if (s == NULL) return NULL;

    /* Make sure added region doesn't contain garbage */
    sh = (void *) (s - (sizeof(struct cls_sdshdr)));
    memset(s + curlen, 0, (len - curlen + 1)); /* also set trailing \0 byte */
    totlen = sh->len + sh->free;
    sh->len = len;
    sh->free = totlen - sh->len;
    return s;
}

/* Append the specified binary-safe string pointed by 't' of 'len' bytes to the
 * end of the specified cls_sds string 's'.
 *
 * After the call, the passed cls_sds string is no longer valid and all the
 * references must be substituted with the new pointer returned by the call. */
cls_sds cls_sdscatlen(cls_sds s, const void *t, size_t len) {
    struct cls_sdshdr *sh;
    size_t curlen = cls_sdslen(s);

    s = sdsMakeRoomFor(s, len);
    if (s == NULL) return NULL;
    sh = (void *) (s - (sizeof(struct cls_sdshdr)));
    memcpy(s + curlen, t, len);
    sh->len = curlen + len;
    sh->free = sh->free - len;
    s[curlen + len] = '\0';
    return s;
}


cls_sds cls_sdscatchar(cls_sds s, char c) {
    struct cls_sdshdr *sh;
    size_t curlen = cls_sdslen(s);

    s = sdsMakeRoomFor(s, 1);
    if (s == NULL) return NULL;
    sh = (void *) (s - (sizeof(struct cls_sdshdr)));
    s[curlen] = c;
    s[curlen + 1] = '\0';
    ++sh->len;
    --sh->free;
    return s;
}


/* Append the specified null termianted C string to the cls_sds string 's'.
 *
 * After the call, the passed cls_sds string is no longer valid and all the
 * references must be substituted with the new pointer returned by the call. */
cls_sds cls_sdscat(cls_sds s, const char *t) {
    if (s == NULL || t == NULL) {
        return s;
    }
    return cls_sdscatlen(s, t, strlen(t));
}

/* Append the specified cls_sds 't' to the existing cls_sds 's'.
 *
 * After the call, the modified cls_sds string is no longer valid and all the
 * references must be substituted with the new pointer returned by the call. */
cls_sds cls_sdscatsds(cls_sds s, const cls_sds t) {
    return cls_sdscatlen(s, t, cls_sdslen(t));
}

/* Destructively modify the cls_sds string 's' to hold the specified binary
 * safe string pointed by 't' of length 'len' bytes. */
cls_sds cls_sdscpylen(cls_sds s, const char *t, size_t len) {
    struct cls_sdshdr *sh = (void *) (s - (sizeof(struct cls_sdshdr)));
    size_t totlen = sh->free + sh->len;

    if (totlen < len) {
        s = sdsMakeRoomFor(s, len - sh->len);
        if (s == NULL) return NULL;
        sh = (void *) (s - (sizeof(struct cls_sdshdr)));
        totlen = sh->free + sh->len;
    }
    memcpy(s, t, len);
    s[len] = '\0';
    sh->len = len;
    sh->free = totlen - len;
    return s;
}

/* Like cls_sdscpylen() but 't' must be a null-termined string so that the length
 * of the string is obtained with strlen(). */
cls_sds cls_sdscpy(cls_sds s, const char *t) {
    return cls_sdscpylen(s, t, strlen(t));
}



/* Like cls_sdscatprintf() but gets va_list instead of being variadic. */
cls_sds cls_sdscatvprintf(cls_sds s, const char *fmt, va_list ap) {
    va_list cpy;
    char staticbuf[1024], *buf = staticbuf, *t;
    size_t buflen = strlen(fmt) * 2;

    /* We try to start using a static buffer for speed.
     * If not possible we revert to heap allocation. */
    if (buflen > sizeof(staticbuf)) {
        buf = malloc(buflen);
        if (buf == NULL) return NULL;
    } else {
        buflen = sizeof(staticbuf);
    }

    /* Try with buffers two times bigger every time we fail to
     * fit the string in the current buffer size. */
    while (1) {
        buf[buflen - 2] = '\0';
        va_copy(cpy, ap);
        vsnprintf(buf, buflen, fmt, cpy);
        va_end(cpy);
        if (buf[buflen - 2] != '\0') {
            if (buf != staticbuf) free(buf);
            buflen *= 2;
            buf = malloc(buflen);
            if (buf == NULL) return NULL;
            continue;
        }
        break;
    }

    /* Finally concat the obtained string to the SDS string and return it. */
    t = cls_sdscat(s, buf);
    if (buf != staticbuf) free(buf);
    return t;
}

/* Append to the cls_sds string 's' a string obtained using printf-alike format
 * specifier.
 *
 * After the call, the modified cls_sds string is no longer valid and all the
 * references must be substituted with the new pointer returned by the call.
 *
 * Example:
 *
 * s = cls_sdsnew("Sum is: ");
 * s = cls_sdscatprintf(s,"%d+%d = %d",a,b,a+b).
 *
 * Often you need to create a string from scratch with the printf-alike
 * format. When this is the need, just use cls_sdsempty() as the target string:
 *
 * s = cls_sdscatprintf(cls_sdsempty(), "... your format ...", args);
 */
cls_sds cls_sdscatprintf(cls_sds s, const char *fmt, ...) {
    va_list ap;
    char *t;
    va_start(ap, fmt);
    t = cls_sdscatvprintf(s, fmt, ap);
    va_end(ap);
    return t;
}


