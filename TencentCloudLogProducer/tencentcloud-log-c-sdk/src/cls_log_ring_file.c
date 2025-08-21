//
//  cls_log_ring_file.c
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/8/20.
//

#include "cls_log_ring_file.h"
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include "cls_log_error.h"
#include "cls_log.h"
#include "cls_sds.h"
#include <stdlib.h>

static void get_ring_file_offset(ring_log_file *file,
                                 uint64_t offset,
                                 int32_t *fileIndex,
                                 int32_t *fileOffset)
{
    *fileIndex = (offset / file->maxFileSize) % file->maxFileCount;
    *fileOffset = offset % file->maxFileSize;
}

static int log_ring_file_open_fd(ring_log_file *file, uint64_t offset, int32_t fileIndex, int32_t fileOffset)
{
    if (file->nowFD > 0 && file->nowFileIndex == fileIndex && file->nowOffset % file->maxFileSize == fileOffset)
    {
        return 0;
    }
    if (file->nowFD > 0)
    {
        close(file->nowFD);
        file->nowFD = -1;
    }
    file->fileRemoveFlags[fileIndex] = 0;
    char filePath[256] = {0};
    snprintf(filePath, 255, "%s_%03d", file->filePath, fileIndex);
    int openFlag = O_RDWR | O_CREAT;
    if (file->syncWrite)
    {
        file->nowFD = open(filePath, openFlag| O_SYNC, 0644);
    }
    else
    {
        file->nowFD = open(filePath, openFlag, 0644);
    }
    if (file->nowFD < 0)
    {
        cls_error_log("open file failed %s, error %s", filePath, strerror(errno));
        return -1;
    }
    if (fileOffset != 0)
    {
        lseek(file->nowFD, fileOffset, SEEK_SET);
    }
    file->nowFileIndex = fileIndex;
    file->nowOffset = offset;
    return 0;
}

ring_log_file *
ring_log_file_open(const char *filePath, int maxFileCount, int maxFileSize, int syncWrite)
{
    ring_log_file *file = (ring_log_file *)malloc(sizeof(ring_log_file));
    memset(file, 0, sizeof(ring_log_file));
    file->filePath = cls_sdsdup((const cls_sds)filePath);
    file->nowFD = -1;
    file->maxFileCount = maxFileCount;
    file->maxFileSize = maxFileSize;
    file->syncWrite = syncWrite;
    file->fileRemoveFlags = (int *)malloc(sizeof(int) * file->maxFileCount);
    memset(file->fileRemoveFlags, 0, sizeof(int) * file->maxFileCount);
    file->fileUseFlags = (int *)malloc(sizeof(int) * file->maxFileCount);
    memset(file->fileUseFlags, 0, sizeof(int) * file->maxFileCount);
    return file;
}

int ring_log_file_write_single(ring_log_file *file, uint64_t offset,
                               const void *buffer,
                               size_t buffer_size)
{
    int32_t fileIndex = 0;
    int32_t fileOffset = 0;
    size_t nowOffset = 0;
    while (nowOffset < buffer_size)
    {
        get_ring_file_offset(file, offset + nowOffset, &fileIndex, &fileOffset);
        if (log_ring_file_open_fd(file, offset, fileIndex, fileOffset) != 0)
        {
            return -1;
        }

        int writeSize = buffer_size - nowOffset;
        if (file->maxFileSize - fileOffset <= writeSize)
        {
            writeSize = file->maxFileSize - fileOffset;
        }

        int rst = write(file->nowFD, (char *)buffer + nowOffset, writeSize);
        if (rst != writeSize)
        {
            cls_error_log("write buffer to file failed, file %s, offset %d, size %d, error %s",
                          file->filePath,
                          fileIndex + nowOffset,
                          file->maxFileSize - fileOffset,
                          strerror(errno));
            return -1;
        }
        nowOffset += rst;
        file->nowOffset += rst;
    }
    return buffer_size;
}

int ring_log_file_write(ring_log_file *file, uint64_t offset, int buffer_count,
                        const void **buffer, size_t *buffer_size)
{
    uint64_t inner_offset = 0;
    for (int(i) = 0; (i) < buffer_count; ++(i))
    {
        if (ring_log_file_write_single(file, offset + inner_offset, buffer[i], buffer_size[i]) != buffer_size[i])
        {
            return -1;
        }
        inner_offset += buffer_size[i];
    }
    return inner_offset;
}

int ring_log_file_read(ring_log_file *file, uint64_t offset, void *buffer,
                       size_t buffer_size)
{
    int32_t fileIndex = 0;
    int32_t fileOffset = 0;
    size_t nowOffset = 0;
    while (nowOffset < buffer_size)
    {
        get_ring_file_offset(file, offset + nowOffset, &fileIndex, &fileOffset);
        if (log_ring_file_open_fd(file, offset, fileIndex, fileOffset) != 0)
        {
            return -1;
        }
        int rst = 0;
        int readSize = buffer_size - nowOffset;
        if (readSize > file->maxFileSize - fileOffset)
        {
            readSize = file->maxFileSize - fileOffset;
        }
        if ((rst = read(file->nowFD, (char *)buffer + nowOffset, readSize)) != readSize)
        {
            if (errno == ENOENT)
            {
                return 0;
            }
            if (rst > 0)
            {
                file->nowOffset += rst;
                nowOffset += rst;
                continue;
            }
            if (rst == 0)
            {
                return file->nowOffset - offset;
            }
            cls_error_log("read buffer from file failed, file %s, offset %d, size %d, error %s",
                          file->filePath,
                          fileIndex + nowOffset,
                          file->maxFileSize - fileOffset,
                          strerror(errno));
            return -1;
        }
        nowOffset += file->maxFileSize - fileOffset;
        file->nowOffset += file->maxFileSize - fileOffset;
    }
    return buffer_size;
}

int ring_log_file_flush(ring_log_file *file)
{
    if (file->nowFD > 0)
    {
        return fsync(file->nowFD);
    }
    return -1;
}

void log_ring_file_remove_file(ring_log_file *file, int32_t fileIndex)
{
    if (file->fileRemoveFlags[fileIndex] > 0)
    {
        return;
    }
    char filePath[256] = {0};
    snprintf(filePath, 255, "%s_%03d", file->filePath, fileIndex);
    remove(filePath);
    cls_info_log("remove file %s", filePath);
    file->fileRemoveFlags[fileIndex] = 1;
}

int ring_log_file_clean(ring_log_file *file, uint64_t startOffset,
                        uint64_t endOffset)
{
    if (endOffset > file->nowOffset)
    {
        cls_error_log("try to clean invalid ring file %s, start %lld, end %lld, now %lld",
                      file->filePath,
                      startOffset,
                      endOffset,
                      file->nowOffset);
        return -1;
    }
    if ((file->nowOffset - endOffset) / file->maxFileSize >= file->maxFileCount - 1)
    {
        // no need to clean
        return 0;
    }
    memset(file->fileUseFlags, 0, sizeof(int) * file->maxFileCount);
    for (int64_t i = endOffset / file->maxFileSize; i <= file->nowOffset / file->maxFileSize; ++i)
    {
        file->fileUseFlags[i % file->maxFileCount] = 1;
    }
    cls_info_log("remove file %s , offset from %lld to %lld, file offset %lld, index from %d to %d",
                 file->filePath,
                 startOffset,
                 endOffset,
                 file->nowOffset,
                 endOffset / file->maxFileSize,
                 file->nowOffset / file->maxFileSize);
    for (int i = 0; i < file->maxFileCount; ++i)
    {
        if (file->fileUseFlags[i] != 0)
            continue;
        log_ring_file_remove_file(file, i);
    }

    return 0;
}

int ring_log_file_close(ring_log_file *file)
{
    if (file != NULL)
    {
        cls_sdsfree(file->filePath);
        if (file->nowFD > 0)
        {
            close(file->nowFD);
            file->nowFD = -1;
        }
        free(file->fileRemoveFlags);
        free(file->fileUseFlags);
        free(file);
    }
    return 0;
}
