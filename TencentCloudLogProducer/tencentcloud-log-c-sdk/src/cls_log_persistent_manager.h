//
//  cls_log_persistent_manager.h
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/8/20.
//

#ifndef cls_log_persistent_manager_h
#define cls_log_persistent_manager_h

#include <stdint.h>
#include "cls_log_polymerization.h"
#include "cls_log_producer_config.h"
#include "cls_log_ring_file.h"
#include "cls_log_producer_manager.h"

typedef struct _log_recovery_checkpoint {
    uint64_t version;
    unsigned char signature[16];
    uint64_t start_file_offset;
    uint64_t now_file_offset;
    int64_t start_log_uuid;
    int64_t now_log_uuid;
    uint64_t check_sum;
    unsigned char preserved[32];
}cls_log_recovery_checkpoint;

typedef struct _log_recovery_item_header
{
    uint64_t magic_code;
    int64_t log_uuid;
    int64_t log_size;
    int64_t logs_count;
    uint64_t preserved;
//    uint16_t len_index[10000];
}cls_log_recovery_item_header;

typedef struct _log_recovery_manager{
    pthread_mutex_t* lock;
    cls_log_recovery_checkpoint checkpoint;
    uint64_t * in_buffer_log_offsets;
    ClsProducerConfig * config;
//    cls_log_group_builder * builder;
    int8_t is_invalid;
    int8_t first_checkpoint_saved;
    ring_log_file * ring_file;

    FILE * checkpoint_file_ptr;
    char * checkpoint_file_path;
    size_t checkpoint_file_size;
}cls_log_recovery_manager;


cls_log_recovery_manager * create_cls_log_recovery_manager(ClsProducerConfig * config);
void destroy_cls_log_recovery_manager(cls_log_recovery_manager * manager);

void on_cls_log_recovery_manager_send_done_uuid(const char * config_name,
                                               int result,
                                               size_t log_bytes,
                                               size_t compressed_bytes,
                                               const char * req_id,
                                               const char * error_message,
                                               const unsigned char * raw_buffer,
                                               void *persistent_manager,
                                                int forceFlush,
                                               int64_t startId,
                                               int64_t endId);

int log_recovery_manager_save_cls_log(cls_log_recovery_manager * manager, cls_log_group_builder *builder);
int log_recovery_manager_is_buffer_enough(cls_log_recovery_manager * manager, cls_log_group_builder *bder,size_t logSize);

int save_cls_log_checkpoint(cls_log_recovery_manager * manager);

int log_persistent_manager_recover_cls_log(cls_log_recovery_manager * manager, ClsProducerManager * producer_manager);

void ResetPersistentLog(cls_log_recovery_manager * manager);


#endif /* cls_log_persistent_manager_h */
