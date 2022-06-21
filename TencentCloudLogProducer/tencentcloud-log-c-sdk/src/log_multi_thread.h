#ifndef LOG_MULTI_THREAD_UTIL_H
#define LOG_MULTI_THREAD_UTIL_H

#include "log_inner_include.h"

#define INVALID_CRITSECT NULL

static inline pthread_mutex_t* InitMutex() {
    pthread_mutex_t* cs = (pthread_mutex_t *)malloc(sizeof(pthread_mutex_t));
    assert(cs != INVALID_CRITSECT);
    pthread_mutex_init(cs, NULL);
    return cs;
}

static inline void DestroyMutex(pthread_mutex_t* cs) {
    if (cs != INVALID_CRITSECT) {
        pthread_mutex_destroy(cs);
        free(cs);
    }
}

static inline pthread_cond_t* InitCond() {
    pthread_cond_t* cond = (pthread_cond_t*)malloc(sizeof(pthread_cond_t));
    assert(cond != INVALID_CRITSECT);
    pthread_cond_init(cond, NULL);
    return cond;
}

static inline void DeleteCond(pthread_cond_t* cond) {
    if (cond != NULL) {
        pthread_cond_destroy(cond);
        free(cond);
    }
}

static inline int COND_WAIT_TIME(pthread_cond_t* cond, pthread_mutex_t* cs, int32_t waitMs) {
    struct timeval now;
    struct timespec outTime;
    gettimeofday(&now, NULL);

    now.tv_usec += ((waitMs) % 1000) * 1000;
    if (now.tv_usec > 1000000)
    {
        now.tv_usec -= 1000000;
        ++now.tv_sec;
    }
    outTime.tv_sec = now.tv_sec + (waitMs) / 1000;
    outTime.tv_nsec = now.tv_usec * 1000;
    return pthread_cond_timedwait(cond, cs, &outTime);
}

static inline int64_t GET_TIME_US() {
    struct timeval now;
    gettimeofday(&now, NULL);
    return (int64_t)now.tv_sec * 1000000 + now.tv_usec;
}


#define THREAD_INIT(thread, func, param) pthread_create(&(thread), NULL, func, param)
#define THREAD_JOIN(thread) pthread_join(thread, NULL)

#define ATOMICINT volatile long

#define ATOMICINT_INC(pAtopicInt) __sync_add_and_fetch(pAtopicInt, 1)
#define ATOMICINT_DEC(pAtopicInt) __sync_add_and_fetch(pAtopicInt, -1)
#define ATOMICINT_ADD(pAtopicInt, addVal) __sync_add_and_fetch(pAtopicInt, addVal)

#endif //LOG_MULTI_THREAD_UTIL_H
