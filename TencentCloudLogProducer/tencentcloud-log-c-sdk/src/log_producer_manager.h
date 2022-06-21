//
// Created by herrylv on 06/5/2022
//

#ifndef LOG_C_SDK_LOG_PRODUCER_MANAGER_H
#define LOG_C_SDK_LOG_PRODUCER_MANAGER_H

#include "log_define.h"
CLS_LOG_CPP_START

#include "log_polymerization.h"
#include "log_multi_thread.h"
#include "log_producer_config.h"
#include "post_logs_client.h"
#include "log_cache_queue.h"

typedef struct {
  ProducerConfig *producerconf;
  volatile uint32_t shutdown;
  volatile uint32_t totalBufferSize;
  log_cache_queue *loggroup_queue;
  log_cache_queue *send_queue;
  pthread_t *send_threads;
  pthread_t flush_thread;
  pthread_mutex_t* lock;
  pthread_cond_t* triger_cond;
  log_group_builder *builder;
  int32_t firstLogTime;
  char *source;
  char *pack_prefix;
  volatile uint32_t pack_index;
  SendCallBackFunc callbackfunc;
  void *user_param;
  log_producer_send_param **send_param_queue;
  uint64_t send_param_queue_size;
  volatile uint64_t send_param_queue_read;
  volatile uint64_t send_param_queue_write;
  ATOMICINT send_thread_count;

} ProducerManager;

extern ProducerManager *
ConstructorProducerManager(ProducerConfig *producerconf);
extern void destroy_log_producer_manager(ProducerManager *manager);

extern int
log_producer_manager_add_log(ProducerManager *producermgr,
                                   int64_t logtime,
                                   int32_t pair_count, char **keys,
                                   int32_t *key_lens, char **values,
                                   int32_t *val_lens, int flush, int64_t uuid);

CLS_LOG_CPP_END

#endif // LOG_C_SDK_LOG_PRODUCER_MANAGER_H
