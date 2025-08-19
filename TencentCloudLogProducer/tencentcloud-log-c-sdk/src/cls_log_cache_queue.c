//
// Created by herrylv on 29/12/2017.
//
#include "cls_log_cache_queue.h"
#include "cls_log_multi_thread.h"


struct _cls_log_queue{
    void ** data;
    int64_t head;
    int64_t tail;
    int64_t size;
    pthread_mutex_t* mutex;
    pthread_cond_t* notempty;
};

cls_log_cache_queue * ConstructClsLogQueue(int64_t size)
{
    void * buffer = malloc(sizeof(void *) * size + sizeof(cls_log_cache_queue));
    memset(buffer, 0, sizeof(void *) * size + sizeof(cls_log_cache_queue));
    cls_log_cache_queue * queue = (cls_log_cache_queue *)buffer;
    queue->data = (void **)((char*)buffer + sizeof(cls_log_cache_queue));
    queue->size = size;
    queue->mutex = InitClsMutex();
    queue->notempty = InitClsCond();
    return queue;
}

void DestroyClsLogQueue(cls_log_cache_queue * queue)
{
    DestroyClsMutex(queue->mutex);
    DeleteClsCond(queue->notempty);
    free(queue);
}

int32_t GetClsLogQueueSize(cls_log_cache_queue * queue)
{
    pthread_mutex_lock(queue->mutex);
    int32_t len = queue->tail - queue->head;
    pthread_mutex_unlock(queue->mutex);
    return len;
}

int32_t CheckClsLogQueueIsFull(cls_log_cache_queue * queue)
{
    pthread_mutex_lock(queue->mutex);
    int32_t rst = (int32_t)((queue->tail - queue->head) == queue->size);
    pthread_mutex_unlock(queue->mutex);
    return rst;
}

int32_t cls_log_queue_push(cls_log_cache_queue * queue, void * data)
{
    pthread_mutex_lock(queue->mutex);
    if (queue->tail - queue->head == queue->size)
    {
        pthread_mutex_unlock(queue->mutex);
        return -1;
    }
    queue->data[queue->tail++ % queue->size] = data;
    pthread_mutex_unlock(queue->mutex);
    pthread_cond_signal(queue->notempty);
    return 0;
}

void * cls_log_queue_pop(cls_log_cache_queue * queue, int32_t waitMs) {
    pthread_mutex_lock(queue->mutex);
    if (queue->tail == queue->head) {
        COND_CLS_WAIT_TIME(queue->notempty, queue->mutex, waitMs);
    }
    void * result = NULL;
    if (queue->tail > queue->head)
    {
        result = queue->data[queue->head++ % queue->size];
    }
    pthread_mutex_unlock(queue->mutex);
    return result;
}

void * cls_log_queue_trypop(cls_log_cache_queue * queue)
{
    pthread_mutex_lock(queue->mutex);
    void * result = NULL;
    if (queue->tail > queue->head)
    {
        result = queue->data[queue->head++ % queue->size];
    }
    pthread_mutex_unlock(queue->mutex);
    return result;
}

