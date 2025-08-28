//
//  cls_log_ring_file.h
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/8/20.
//

#ifndef cls_log_ring_file_h
#define cls_log_ring_file_h

#include <stdio.h>

typedef struct _ring_log_file
{
    char * filePath;
    int maxFileCount;
    int maxFileSize;
    int syncWrite;

    int nowFileIndex;
    uint64_t nowOffset;
    int nowFD;
    int *fileRemoveFlags;
    int *fileUseFlags;
}ring_log_file;

ring_log_file * ring_log_file_open(const char * filePath, int maxFileCount, int maxFileSize, int syncWrite);
int ring_log_file_write(ring_log_file * file, uint64_t offset, int buffer_count, const void * buffer[], size_t buffer_size[]);
int ring_log_file_write_single(ring_log_file * file, uint64_t offset, const void * buffer, size_t buffer_size);
int ring_log_file_read(ring_log_file * file, uint64_t offset, void * buffer, size_t buffer_size);
int ring_log_file_flush(ring_log_file * file);
int ring_log_file_clean(ring_log_file * file, uint64_t startOffset, uint64_t endOffset);
int ring_log_file_close(ring_log_file * file);
void log_ring_file_remove_file(ring_log_file *file, int32_t fileIndex);

#endif /* cls_log_ring_file_h */
