//
//  cls_log_persistent_manager.c
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/8/20.
//

#include "cls_log_persistent_manager.h"
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include "cls_log.h"
#include "cls_log_error.h"
#include <pthread.h>
#include "cls_sds.h"


#define MAX_CHECKPOINT_FILE_SIZE (sizeof(cls_log_recovery_checkpoint) * 1024)
#define LOG_PERSISTENT_HEADER_MAGIC (0xf7216a5b76df67f5)

static int32_t is_valid_log_checkpoint(cls_log_recovery_checkpoint *checkpoint)
{
    return checkpoint->check_sum == checkpoint->start_log_uuid + checkpoint->now_log_uuid +
                                        checkpoint->start_file_offset + checkpoint->now_file_offset;
}

static int32_t recover_log_checkpoint(cls_log_recovery_manager *manager)
{
    FILE *tmpFile = fopen(manager->checkpoint_file_path, "rb");
    if (tmpFile == NULL)
    {
        if (errno == ENOENT)
        {
            return 0;
        }
        return -1;
    }
    fseek(tmpFile, 0, SEEK_END);
    long pos = ftell(tmpFile);
    if (pos == 0)
    {
        // empty file
        return 0;
    }
    long fixedPos = pos - pos % sizeof(cls_log_recovery_checkpoint);
    long lastPos = fixedPos == 0 ? 0 : fixedPos - sizeof(cls_log_recovery_checkpoint);
    fseek(tmpFile, lastPos, SEEK_SET);
    if (1 != fread((void *)&(manager->checkpoint), sizeof(cls_log_recovery_checkpoint), 1, tmpFile))
    {
        fclose(tmpFile);
        return -2;
    }
    if (!is_valid_log_checkpoint(&(manager->checkpoint)))
    {
        fclose(tmpFile);
        return -3;
    }
    fclose(tmpFile);
    manager->checkpoint_file_size = pos;
    return 0;
}

int save_cls_log_checkpoint(cls_log_recovery_manager *manager)
{
    cls_log_recovery_checkpoint *checkpoint = &(manager->checkpoint);
    checkpoint->check_sum = checkpoint->start_log_uuid + checkpoint->now_log_uuid +
                            checkpoint->start_file_offset + checkpoint->now_file_offset;
    if (manager->checkpoint_file_size >= MAX_CHECKPOINT_FILE_SIZE)
    {
        if (manager->checkpoint_file_ptr != NULL)
        {
            fclose(manager->checkpoint_file_ptr);
            manager->checkpoint_file_ptr = NULL;
        }
        char tmpFilePath[256];
        strcpy(tmpFilePath, manager->checkpoint_file_path);
        strcat(tmpFilePath, ".bak");
        cls_info_log("start switch checkpoint index file %s \n", manager->checkpoint_file_path);
        FILE *tmpFile = fopen(tmpFilePath, "wb+");
        if (tmpFile == NULL)
            return -1;
        if (1 !=
            fwrite((const void *)(&manager->checkpoint), sizeof(cls_log_recovery_checkpoint), 1, tmpFile))
        {
            fclose(tmpFile);
            return -2;
        }
        if (fclose(tmpFile) != 0)
            return -3;
        if (rename(tmpFilePath, manager->checkpoint_file_path) != 0)
            return -4;
        manager->checkpoint_file_size = sizeof(cls_log_recovery_checkpoint);
        return 0;
    }
    if (manager->checkpoint_file_ptr == NULL)
    {
        manager->checkpoint_file_ptr = fopen(manager->checkpoint_file_path, "ab+");
        if (manager->checkpoint_file_ptr == NULL)
            return -5;
    }
    if (1 !=
        fwrite((const void *)(&manager->checkpoint), sizeof(cls_log_recovery_checkpoint), 1, manager->checkpoint_file_ptr))
        return -6;
    if (fflush(manager->checkpoint_file_ptr) != 0)
        return -7;
    manager->checkpoint_file_size += sizeof(cls_log_recovery_checkpoint);
    return 0;
}

void on_cls_log_recovery_manager_send_done_uuid(const char *config_name,
                                              int result,
                                              size_t log_bytes,
                                              size_t compressed_bytes,
                                              const char *req_id,
                                              const char *error_message,
                                              const unsigned char *raw_buffer,
                                              void *persistent_manager,
                                              int64_t startId,
                                              int64_t endId)
{
    if (result >= CLS_HTTP_INTERNAL_SERVER_ERROR || result == CLS_HTTP_TOO_MANY_REQUESTS || result == CLS_HTTP_REQUEST_TIMEOUT || result == CLS_HTTP_FORBIDDEN){
        return;
    }
    cls_log_recovery_manager *manager = (cls_log_recovery_manager *)persistent_manager;
    if (manager == NULL)
    {
        return;
    }
    if (manager->is_invalid)
    {
        return;
    }
    if (startId < 0 || endId < 0 || startId > endId || endId - startId > 1024 * 1024)
    {
        cls_fatal_log("invalid id range %lld %lld", startId, endId);
        manager->is_invalid = 1;
        return;
    }

    // multi thread send is not allowed, and this should never happen
    if (startId > manager->checkpoint.start_log_uuid)
    {
        cls_fatal_log("topic %s, invalid checkpoint start log uuid %lld %lld",
                      manager->config->topic,
                      startId,
                      manager->checkpoint.start_log_uuid);
        manager->is_invalid = 1;
        return;
    }
    pthread_mutex_lock(manager->lock);

    uint64_t last_offset = manager->checkpoint.start_file_offset;
    manager->checkpoint.start_file_offset = manager->in_buffer_log_offsets[endId % manager->config->maxPersistentLogCount];
    manager->checkpoint.start_log_uuid = endId + 1;
    int rst = save_cls_log_checkpoint(manager);
    if (rst != 0)
    {
        cls_error_log("topic %s, save checkpoint failed, reason %d",
                      manager->config->topic,
                      rst);
    }
    ring_log_file_clean(manager->ring_file, last_offset, manager->checkpoint.start_file_offset);

    pthread_mutex_unlock(manager->lock);
}

static void log_persistent_manager_init(cls_log_recovery_manager *manager, ClsProducerConfig *config)
{
    memset(manager, 0, sizeof(cls_log_recovery_manager));
//    manager->builder = GenerateClsLogGroup();
    manager->checkpoint.start_log_uuid = (int64_t)(time(NULL)) * 1000LL * 1000LL * 1000LL;
    manager->checkpoint.now_log_uuid = manager->checkpoint.start_log_uuid;
    manager->config = config;
    pthread_mutex_t* cs = (pthread_mutex_t *)malloc(sizeof(pthread_mutex_t));
    assert(cs != INVALID_CRITSECT);
    pthread_mutex_init(cs, NULL);
    manager->lock = cs;
    manager->checkpoint_file_path = cls_sdscat(cls_sdsdup(config->persistentFilePath), ".idx");
    manager->in_buffer_log_offsets = (uint64_t *)malloc(sizeof(uint64_t) * config->maxPersistentLogCount);
    memset(manager->in_buffer_log_offsets, 0, sizeof(uint64_t) * config->maxPersistentLogCount);
    manager->ring_file = ring_log_file_open(config->persistentFilePath, config->maxPersistentFileCount, config->maxPersistentFileSize, config->forceFlushDisk);
}

static void log_persistent_manager_clear(cls_log_recovery_manager *manager)
{
//    cls_log_group_destroy(manager->builder);
    if (manager->lock != INVALID_CRITSECT) {
        pthread_mutex_destroy(manager->lock);
        free(manager->lock);
    }
    if (manager->checkpoint_file_ptr != NULL)
    {
        fclose(manager->checkpoint_file_ptr);
        manager->checkpoint_file_ptr = NULL;
    }
    free(manager->in_buffer_log_offsets);
    cls_sdsfree(manager->checkpoint_file_path);
    ring_log_file_close(manager->ring_file);
}

cls_log_recovery_manager *
create_cls_log_recovery_manager(ClsProducerConfig *config)
{
    if (!log_producer_persistent_config_is_enabled(config))
    {
        return NULL;
    }
    cls_log_recovery_manager *manager = (cls_log_recovery_manager *)malloc(sizeof(cls_log_recovery_manager));
    log_persistent_manager_init(manager, config);
    return manager;
}

void destroy_cls_log_recovery_manager(cls_log_recovery_manager *manager)
{
    if (manager == NULL)
    {
        return;
    }
    log_persistent_manager_clear(manager);
    free(manager);
}

int log_recovery_manager_save_cls_log(cls_log_recovery_manager *manager,
                                      cls_log_group_builder *builder)
{
    const char *logBuf = builder->grp->logs.buffer;
    size_t logSize = builder->grp->logs.now_buffer_len;
    // save binlog
    const void *buffer[2];
    size_t bufferSize[2];
    cls_log_recovery_item_header header;
    header.magic_code = LOG_PERSISTENT_HEADER_MAGIC;
    header.log_uuid = manager->checkpoint.now_log_uuid;
    header.log_size = logSize;
    header.logs_count = builder->grp->logs_count;
    header.preserved = 0;
    memcpy(header.len_index, builder->grp->logs.buf_index, builder->grp->logs_count * sizeof(uint16_t));
    for(int i = 0; i < builder->grp->logs_count; ++i){
        header.len_index[i] = builder->grp->logs.buf_index[i];
    }

    buffer[0] = &header;
    buffer[1] = logBuf;
    bufferSize[0] = sizeof(cls_log_recovery_item_header);
    bufferSize[1] = logSize;
    int rst = ring_log_file_write(manager->ring_file, manager->checkpoint.now_file_offset, 2, buffer, bufferSize);
    if (rst != bufferSize[0] + bufferSize[1])
    {
        cls_error_log("topic %s, write bin log failed, rst %d",
                      manager->config->topic,
                      rst);
        return CLS_LOG_PRODUCER_PERSISTENT_ERROR;
    }
    manager->checkpoint.now_file_offset += rst;
    // update in memory checkpoint
    manager->in_buffer_log_offsets[manager->checkpoint.now_log_uuid % manager->config->maxPersistentLogCount] = manager->checkpoint.now_file_offset;
    ++manager->checkpoint.now_log_uuid;
    cls_debug_log("topic %s,write bin log success, offset %lld, uuid %lld, log size %d",
                  manager->config->topic,
                  manager->checkpoint.now_file_offset,
                  manager->checkpoint.now_log_uuid,
                  rst);
    if (manager->first_checkpoint_saved == 0)
    {
        save_cls_log_checkpoint(manager);
        manager->first_checkpoint_saved = 1;
    }
    return 0;
}

int log_recovery_manager_is_buffer_enough(cls_log_recovery_manager *manager,
                                            size_t logSize)
{
    if (manager->checkpoint.now_file_offset < manager->checkpoint.start_file_offset)
    {
        cls_fatal_log("topic %s, persistent manager is invalid, file offset error, %lld %lld",
                      manager->config->topic,
                      manager->checkpoint.now_file_offset,
                      manager->checkpoint.start_file_offset);
        manager->is_invalid = 1;
        return 0;
    }
    if (manager->checkpoint.now_file_offset - manager->checkpoint.start_file_offset + logSize + 1024 >
            (uint64_t)manager->config->maxPersistentFileCount * manager->config->maxPersistentFileSize &&
        manager->checkpoint.now_log_uuid - manager->checkpoint.start_log_uuid < manager->config->maxPersistentLogCount - 1)
    {
        printf("now_file_offset:%lld|start_file_offset:%lld|logSize:%lld|now_log_uuid:%lld|start_log_uuid:%lld\n",manager->checkpoint.now_file_offset,manager->checkpoint.start_file_offset,logSize,manager->checkpoint.now_log_uuid,manager->checkpoint.start_log_uuid);
        return 0;
    }
    return 1;
}

static int log_persistent_manager_recover_inner(cls_log_recovery_manager *manager,
                                                ClsProducerManager *producer_manager)
{
    int rst = recover_log_checkpoint(manager);
    if (rst != 0)
    {
        return rst;
    }

    cls_info_log("topic %s, recover persistent checkpoint success, checkpoint %lld %lld %lld %lld",
                 manager->config->topic,
                 manager->checkpoint.start_file_offset,
                 manager->checkpoint.now_file_offset,
                 manager->checkpoint.start_log_uuid,
                 manager->checkpoint.now_log_uuid);

    if (manager->checkpoint.start_file_offset == 0 && manager->checkpoint.now_file_offset == 0)
    {
        // no need to recover
        return 0;
    }

    // try recover ring file

    cls_log_recovery_item_header header;

    uint64_t fileOffset = manager->checkpoint.start_file_offset;
    int64_t logUUID = manager->checkpoint.start_log_uuid;

    char *buffer = NULL;
    int max_buffer_size = 0;

    while (1)
    {
        rst = ring_log_file_read(manager->ring_file, fileOffset, &header, sizeof(cls_log_recovery_item_header));
        if (rst != sizeof(cls_log_recovery_item_header))
        {
            if (rst == 0)
            {
                cls_info_log("topic %s,  read end of file",
                             manager->config->topic);
                if (buffer != NULL)
                {
                    free(buffer);
                    buffer = NULL;
                }
                break;
            }
            cls_error_log("topic %s,  read binlog file header failed, offset %lld, result %d",
                          manager->config->topic,
                          fileOffset,
                          rst);
            if (buffer != NULL)
            {
                free(buffer);
                buffer = NULL;
            }
            return -1;
        }
        if (header.magic_code != LOG_PERSISTENT_HEADER_MAGIC ||
            header.log_uuid < logUUID ||
            header.log_size <= 0 || header.log_size > 10 * 1024 * 1024)
        {
            cls_info_log("topic %s, read binlog file fail, invalid header: uuid %lld expect %lld",
                         manager->config->topic,
                         header.log_uuid,
                         logUUID);
            break;
        }
        if (buffer == NULL || max_buffer_size < header.log_size)
        {
            if (buffer != NULL)
            {
                free(buffer);
            }
            buffer = (char *)malloc(header.log_size * 2);
            max_buffer_size = header.log_size * 2;
        }
        rst = ring_log_file_read(manager->ring_file, fileOffset + sizeof(cls_log_recovery_item_header), buffer, header.log_size);
        if (rst != header.log_size)
        {
            // if read fail, just break
            cls_warn_log("project %s, read binlog file content failed, offset %lld, result %d",
                         manager->config->topic,
                         fileOffset + sizeof(cls_log_recovery_item_header),
                         rst);
            break;
        }
        if (header.log_uuid - logUUID > 1024 * 1024)
        {
            cls_error_log("topic %s, log uuid jump, %lld %lld",
                          manager->config->topic,
                          header.log_uuid,
                          logUUID);
            if (buffer != NULL)
            {
                free(buffer);
                buffer = NULL;
            }
            return -3;
        }
        // set empty log uuid len 0
        for (int64_t emptyUUID = logUUID + 1; emptyUUID < header.log_uuid; ++emptyUUID)
        {
            manager->in_buffer_log_offsets[emptyUUID % manager->config->maxPersistentLogCount] = 0;
        }

        logUUID = header.log_uuid;
        fileOffset += header.log_size + sizeof(cls_log_recovery_item_header);
        manager->in_buffer_log_offsets[header.log_uuid % manager->config->maxPersistentLogCount] = fileOffset;
        printf("logbuflen:%ld|logSize:%ld\n",strlen(buffer),header.log_size);
        rst = log_producer_manager_add_log_raw(producer_manager, buffer, header.log_size, 0, header.log_uuid, header.len_index,header.logs_count);
        if (rst != 0)
        {
            cls_error_log("topic %s, add log to producer manager failed, this log will been dropped",
                          manager->config->topic);
        }
    }
    if (buffer != NULL)
    {
        free(buffer);
        buffer = NULL;
    }

    if (logUUID < manager->checkpoint.now_log_uuid - 1)
    {
        // replay fail
        cls_fatal_log("topic %s, replay bin log failed, now log uuid %lld, expected min log uuid %lld, start uuid %lld, start offset  %lld, now offset  %lld, replayed offset %lld",
                      manager->config->topic,
                      logUUID,
                      manager->checkpoint.now_log_uuid,
                      manager->checkpoint.start_log_uuid,
                      manager->checkpoint.start_file_offset,
                      manager->checkpoint.now_file_offset,
                      fileOffset);
        return -4;
    }

    // update new checkpoint when replay bin log success
    if (fileOffset > manager->checkpoint.start_file_offset)
    {
        manager->checkpoint.now_log_uuid = logUUID + 1;
        manager->checkpoint.now_file_offset = fileOffset;
    }

    cls_info_log("topic %s, replay bin log success, now checkpoint %lld %lld %lld %lld",
                 manager->config->topic,
                 manager->checkpoint.start_log_uuid,
                 manager->checkpoint.now_log_uuid,
                 manager->checkpoint.start_file_offset,
                 manager->checkpoint.now_file_offset);

    // save new checkpoint
    rst = save_cls_log_checkpoint(manager);
    if (rst != 0)
    {
        cls_error_log("topic %s, save checkpoint failed, reason %d",
                      manager->config->topic,
                      rst);
    }
    return rst;
}

static void log_persistent_manager_reset(cls_log_recovery_manager *manager)
{
    ClsProducerConfig *config = manager->config;
    log_persistent_manager_clear(manager);
    log_persistent_manager_init(manager, config);
    manager->checkpoint.start_log_uuid = (int64_t)(time(NULL)) * 1000LL * 1000LL * 1000LL + 500LL * 1000LL * 1000LL;
    manager->checkpoint.now_log_uuid = manager->checkpoint.start_log_uuid;
    manager->is_invalid = 0;
}

int log_persistent_manager_recover_cls_log(cls_log_recovery_manager *manager,
                                   ClsProducerManager *producer_manager)
{
    cls_info_log("topic %s, start recover persistent manager",
                 manager->config->topic);
    pthread_mutex_lock(manager->lock);
    int rst = log_persistent_manager_recover_inner(manager, producer_manager);
    if (rst != 0)
    {
        // if recover failed, reset persistent manager
        manager->is_invalid = 1;
        log_persistent_manager_reset(manager);
    }
    else
    {
        manager->is_invalid = 0;
    }
    pthread_mutex_unlock(manager->lock);
    return rst;
}
