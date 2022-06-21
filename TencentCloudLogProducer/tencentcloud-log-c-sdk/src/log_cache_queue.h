//
// Created by herrylv on 29/12/2017.
//

#ifndef LOG_C_SDK_LOG_QUEUE_H
#define LOG_C_SDK_LOG_QUEUE_H

#include <stdint.h>

typedef struct _log_queue log_cache_queue;

log_cache_queue *ConstructLogQueue(int64_t max_size);

void DestroyLogQueue(log_cache_queue *queue);

int32_t GetLogQueueSize(log_cache_queue *queue);

int32_t CheckLogQueueIsFull(log_cache_queue *queue);

int32_t log_queue_push(log_cache_queue *queue, void *data);

void *log_queue_pop(log_cache_queue *queue, int32_t waitMs);

void *log_queue_trypop(log_cache_queue *queue);

#endif // LOG_C_SDK_LOG_QUEUE_H
