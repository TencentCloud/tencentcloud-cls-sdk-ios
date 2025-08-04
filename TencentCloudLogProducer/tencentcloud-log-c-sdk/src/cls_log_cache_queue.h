//
// Created by herrylv on 29/12/2017.
//

#ifndef CLS_LOG_C_SDK_LOG_QUEUE_H
#define CLS_LOG_C_SDK_LOG_QUEUE_H

#include <stdint.h>

typedef struct _cls_log_queue cls_log_cache_queue;

cls_log_cache_queue *ConstructClsLogQueue(int64_t max_size);

void DestroyClsLogQueue(cls_log_cache_queue *queue);

int32_t GetClsLogQueueSize(cls_log_cache_queue *queue);

int32_t CheckClsLogQueueIsFull(cls_log_cache_queue *queue);

int32_t cls_log_queue_push(cls_log_cache_queue *queue, void *data);

void *cls_log_queue_pop(cls_log_cache_queue *queue, int32_t waitMs);

void *cls_log_queue_trypop(cls_log_cache_queue *queue);

#endif // CLS_LOG_C_SDK_LOG_QUEUE_H
