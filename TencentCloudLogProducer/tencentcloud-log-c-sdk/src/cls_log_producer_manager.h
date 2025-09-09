//
// Created by herrylv on 06/5/2022
//

#ifndef CLS_LOG_C_SDK_LOG_PRODUCER_MANAGER_H
#define CLS_LOG_C_SDK_LOG_PRODUCER_MANAGER_H

#include "cls_log_define.h"
CLS_LOG_CPP_START

#include "cls_log_polymerization.h"
#include "cls_log_multi_thread.h"
#include "cls_log_producer_config.h"
#include "cls_post_logs_client.h"
#include "cls_log_cache_queue.h"

typedef struct {
    ClsProducerConfig *producerconf;
  volatile uint32_t shutdown;
  volatile uint32_t totalBufferSize;
  cls_log_cache_queue *loggroup_queue;
  cls_log_cache_queue *send_queue;
  pthread_t *send_threads;
  pthread_t flush_thread;
  pthread_mutex_t* lock;
  pthread_cond_t* triger_cond;
  cls_log_group_builder *builder;
  int32_t firstLogTime;
  char *source;
  char *pack_prefix;
  volatile uint32_t pack_index;
  ClsSendCallBackFunc callbackfunc;
  void *user_param;
  cls_log_producer_send_param **send_param_queue;
  uint64_t send_param_queue_size;
  volatile uint64_t send_param_queue_read;
  volatile uint64_t send_param_queue_write;
  CLSATOMICINT send_thread_count;
    
  on_cls_log_producer_send_done_function send_done_persistent_function;
  void * uuid_user_param;

} ClsProducerManager;

extern ClsProducerManager *
ConstructorClsProducerManager(ClsProducerConfig *producerconf);
extern void destroy_cls_log_producer_manager(ClsProducerManager *manager);

extern int
cls_log_producer_manager_add_log(ClsProducerManager *producermgr,
                                   int64_t logtime,
                                   int32_t pair_count, char **keys,
                                   int32_t *key_lens, char **values,
                                   int32_t *val_lens, int flush, int64_t uuid);

extern int log_producer_manager_add_log_raw(ClsProducerManager * producer_manager,
                                                             char * logBuf,
                                                             size_t logSize,
                                                             int flush,
                                                             int64_t uuid,int* len_index,int64_t logs_count);

CLS_LOG_CPP_END

#endif // CLS_LOG_C_SDK_LOG_PRODUCER_MANAGER_H
