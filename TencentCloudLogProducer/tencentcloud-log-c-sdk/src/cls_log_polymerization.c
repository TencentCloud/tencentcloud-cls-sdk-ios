#include "cls_log_polymerization.h"
#include "cls_logs.pb-c.h"
#include "cls_lz4.h"
#include "cls_sds.h"
#include <string.h>
#include <stdio.h>
#include <assert.h>
#include <sys/time.h>

// 1+3( 1 --->  header;  2 ---> 128 * 128 = 16KB)
#define INIT_CLS_LOG_SIZE_BYTES 3

/**
 * Return the number of bytes required to store a variable-length unsigned
 * 32-bit integer in base-128 varint encoding.
 *
 * \param v
 *      Value to encode.
 * \return
 *      Number of bytes required.
 */
static inline size_t uint32_size(uint32_t v)
{
    if (v < (1UL << 7))
    {
        return 1;
    }
    else if (v < (1UL << 14))
    {
        return 2;
    }
    else if (v < (1UL << 21))
    {
        return 3;
    }
    else if (v < (1UL << 28))
    {
        return 4;
    }
    else
    {
        return 5;
    }
}

/**
 * Pack an unsigned 32-bit integer in base-128 varint encoding and return the
 * number of bytes written, which must be 5 or less.
 *
 * \param value
 *      Value to encode.
 * \param[out] out
 *      Packed value.
 * \return
 *      Number of bytes written to `out`.
 */
static inline size_t uint32_pack(uint32_t value, uint8_t *out)
{
    unsigned rv = 0;

    if (value >= 0x80)
    {
        out[rv++] = value | 0x80;
        value >>= 7;
        if (value >= 0x80)
        {
            out[rv++] = value | 0x80;
            value >>= 7;
            if (value >= 0x80)
            {
                out[rv++] = value | 0x80;
                value >>= 7;
                if (value >= 0x80)
                {
                    out[rv++] = value | 0x80;
                    value >>= 7;
                }
            }
        }
    }
    /* assert: value<128 */
    out[rv++] = value;
    return rv;
}

static inline uint32_t parse_uint32(unsigned len, const uint8_t *data)
{
    uint32_t rv = data[0] & 0x7f;
    if (len > 1)
    {
        rv |= ((uint32_t)(data[1] & 0x7f) << 7);
        if (len > 2)
        {
            rv |= ((uint32_t)(data[2] & 0x7f) << 14);
            if (len > 3)
            {
                rv |= ((uint32_t)(data[3] & 0x7f) << 21);
                if (len > 4)
                    rv |= ((uint32_t)(data[4]) << 28);
            }
        }
    }
    return rv;
}

static unsigned scan_varint(unsigned len, const uint8_t *data)
{
    unsigned i;
    if (len > 10)
        len = 10;
    for (i = 0; i < len; i++)
        if ((data[i] & 0x80) == 0)
            break;
    if (i == len)
        return 0;
    return i + 1;
}

cls_log_group_builder *GenerateClsLogGroup()
{
    cls_log_group_builder *bder = (cls_log_group_builder *)malloc(sizeof(cls_log_group_builder) + sizeof(cls_log_group));
    memset(bder, 0, sizeof(cls_log_group_builder) + sizeof(cls_log_group));
    bder->grp = (cls_log_group *)((char *)(bder) + sizeof(cls_log_group_builder));
    bder->loggroup_size = sizeof(cls_log_group) + sizeof(cls_log_group_builder);
    bder->create_time = time(NULL);
    return bder;
}

void cls_log_group_destroy(cls_log_group_builder *bder)
{
    // free tag
    cls_log_group *group = bder->grp;
    if (group->tags.buffer != NULL)
    {
        free(group->tags.buffer);
    }
    if (group->tags.buf_index != NULL)
    {
        free(group->tags.buf_index);
    }
    // free log
    if (group->logs.buffer != NULL)
    {
        free(group->logs.buffer);
    }
    if (group->logs.buf_index != NULL)
    {
        free(group->logs.buf_index);
    }
    if (group->topic != NULL)
    {
        cls_sdsfree(group->topic);
    }
    if (group->source != NULL)
    {
        cls_sdsfree(group->source);
    }
    free(bder);
}

/**
 * adjust buffer, this function will ensure tag's buffer size >= tag->now_buffer_len + new_len
 * @param tag
 * @param new_len new buffer len
 */
void _adjust_cls_buffer(cls_log_buffer *tag, uint32_t new_len)
{
    if (tag->buffer == NULL)
    {
        tag->buffer = (char *)malloc(new_len << 2);
        tag->max_buffer_len = new_len << 2;
        tag->now_buffer = tag->buffer;
        tag->now_buffer_len = 0;
        tag->buf_index = (int*)malloc(new_len << 2);
        memset(tag->buf_index,0,new_len << 2);
        return;
    }
    uint32_t new_buffer_len = tag->max_buffer_len << 1;

    if (new_buffer_len < tag->now_buffer_len + new_len)
    {
        new_buffer_len = tag->now_buffer_len + new_len;
    }

    tag->buffer = (char *)realloc(tag->buffer, new_buffer_len);
    tag->buf_index = (int*)realloc(tag->buf_index, new_buffer_len);
    tag->now_buffer = tag->buffer + tag->now_buffer_len;
    tag->max_buffer_len = new_buffer_len;
}

void add_cls_log_raw(cls_log_group_builder *bder, const char *buffer, size_t size)
{
    ++bder->grp->logs_count;
    cls_log_buffer *log = &(bder->grp->logs);
    if (log->now_buffer == NULL || log->max_buffer_len < log->now_buffer_len + size)
    {
        _adjust_cls_buffer(log, size);
    }
    memcpy(log->now_buffer, buffer, size);
    bder->loggroup_size += size;
    log->now_buffer_len += size;
    log->now_buffer += size;
}

void add_cls_log_full(cls_log_group_builder *bder, uint32_t logTime, int32_t pair_count, char **keys, size_t *key_lens, char **values, size_t *val_lens)
{
    ++bder->grp->logs_count;

    int32_t i = 0;
    int32_t logSize = 6;
    for (; i < pair_count; ++i)
    {
        uint32_t contSize = uint32_size(key_lens[i]) + uint32_size(val_lens[i]) + key_lens[i] + val_lens[i] + 2;
        logSize += 1 + uint32_size(contSize) + contSize;
    }
    int32_t totalBufferSize = logSize + 1 + uint32_size(logSize);

    cls_log_buffer *log = &(bder->grp->logs);

    if (log->now_buffer == NULL || log->max_buffer_len < log->now_buffer_len + totalBufferSize)
    {
        _adjust_cls_buffer(log, totalBufferSize);
    }

    bder->loggroup_size += totalBufferSize;
    uint8_t *buf = (uint8_t *)log->now_buffer;

    *buf++ = 0x0A;
    buf += uint32_pack(logSize, buf);

    // time
    *buf++ = 0x08;
    buf += uint32_pack(logTime, buf);

    // Content
    // header
    i = 0;
    for (; i < pair_count; ++i)
    {
        *buf++ = 0x12;
        buf += uint32_pack(uint32_size(key_lens[i]) + uint32_size(val_lens[i]) + 2 + key_lens[i] + val_lens[i], buf);
        *buf++ = 0x0A;
        buf += uint32_pack(key_lens[i], buf);
        memcpy(buf, keys[i], key_lens[i]);
        buf += key_lens[i];
        *buf++ = 0x12;
        buf += uint32_pack(val_lens[i], buf);
        memcpy(buf, values[i], val_lens[i]);
        buf += val_lens[i];
    }
    assert(buf - (uint8_t *)log->now_buffer == totalBufferSize);
    log->now_buffer_len += totalBufferSize;
    log->now_buffer = (char *)buf;
}

void AddClsSource(cls_log_group_builder *bder, const char *src, size_t len)
{
    bder->loggroup_size += sizeof(char) * (len) + uint32_size((uint32_t)len) + 1;
    bder->grp->source = cls_sdsnewlen(src, len);
}

void AddClsTopic(cls_log_group_builder *bder, const char *tpc, size_t len)
{
    bder->loggroup_size += sizeof(char) * (len) + uint32_size((uint32_t)len) + 1;
    bder->grp->topic = cls_sdsnewlen(tpc, len);
}

void AddClsPackageId(cls_log_group_builder *bder, const char *pack, size_t pack_len, size_t packNum)
{
    char packStr[128];
    packStr[127] = '\0';
    snprintf(packStr, 127, "%s-%X", pack, (unsigned int)packNum);
    AddClsTag(bder, "__pack_id__", strlen("__pack_id__"), packStr, strlen(packStr));
}

void AddClsTag(cls_log_group_builder *bder, const char *k, size_t k_len, const char *v, size_t v_len)
{
    // use only 1 malloc
    uint32_t tag_size = sizeof(char) * (k_len + v_len) + uint32_size((uint32_t)k_len) + uint32_size((uint32_t)v_len) + 2;
    uint32_t n_buffer = 1 + uint32_size(tag_size) + tag_size;
    cls_log_buffer *tag = &(bder->grp->tags);
    if (tag->now_buffer == NULL || tag->now_buffer_len + n_buffer > tag->max_buffer_len)
    {
        _adjust_cls_buffer(tag, n_buffer);
    }
    uint8_t *buf = (uint8_t *)tag->now_buffer;
    *buf++ = 0x32;
    buf += uint32_pack(tag_size, buf);
    *buf++ = 0x0A;
    buf += uint32_pack((uint32_t)k_len, buf);
    memcpy(buf, k, k_len);
    buf += k_len;
    *buf++ = 0x12;
    buf += uint32_pack((uint32_t)v_len, buf);
    memcpy(buf, v, v_len);
    buf += v_len;
    assert((uint8_t *)tag->now_buffer + n_buffer == buf);
    tag->now_buffer = (char *)buf;
    tag->now_buffer_len += n_buffer;
    bder->loggroup_size += n_buffer;
}

static uint32_t _cls_log_pack(cls_log_group *grp, uint8_t *buf)
{
    uint8_t *start_buf = buf;

    if (grp->logs.buffer != NULL)
    {
        buf += grp->logs.now_buffer_len;
    }
    else
    {
        return 0;
    }

    if (grp->topic != NULL)
    {
        *buf++ = 0x1A;
        buf += uint32_pack((uint32_t)cls_sdslen(grp->topic), buf);
        memcpy(buf, grp->topic, cls_sdslen(grp->topic));
        buf += cls_sdslen(grp->topic);
    }

    if (grp->source != NULL)
    {
        *buf++ = 0x22;
        buf += uint32_pack((uint32_t)cls_sdslen(grp->source), buf);
        memcpy(buf, grp->source, cls_sdslen(grp->source));
        buf += cls_sdslen(grp->source);
    }

    if (grp->tags.buffer != NULL)
    {
        memcpy(buf, grp->tags.buffer, grp->tags.now_buffer_len);
        buf += grp->tags.now_buffer_len;
    }

    return buf - start_buf;
}

cls_lz4_content *ClsSerializeWithNolz4(cls_log_group_builder *bder)
{
    cls_log_buffer *log = &(bder->grp->logs);
    int log_count =bder->grp->logs_count;
    Cls__Log **pcls_log = (Cls__Log **)malloc(sizeof(Cls__Log *) * bder->grp->logs_count);
    uint8_t *data = log->buffer;
    for (int i = 0; i < bder->grp->logs_count; ++i)
    {
        pcls_log[i] = cls__log__unpack(NULL, (log->buf_index)[i], data);
        data += (log->buf_index)[i];
        if (pcls_log[i] == NULL)
        {
            return NULL;
        }
    }

    Cls__LogGroupList pbLogGroup = CLS__LOG_GROUP_LIST__INIT;
    Cls__LogGroup **loggroups = malloc(sizeof(Cls__LogGroup *));
    loggroups[0] = malloc(sizeof(Cls__LogGroup));
    cls__log_group__init(loggroups[0]);
    loggroups[0]->logs_count = bder->grp->logs_count;;
    loggroups[0]->logs = pcls_log;
    pbLogGroup.loggrouplist = loggroups;
    pbLogGroup.n_loggrouplist = 1;
    unsigned len = cls__log_group_list__get_packed_size(&pbLogGroup);
    void *group_list_buf = malloc(len);
    cls__log_group_list__pack(&pbLogGroup, group_list_buf);

    cls_lz4_content *pLogbuf = (cls_lz4_content *)malloc(sizeof(cls_lz4_content) + len);
    pLogbuf->length = len;
    pLogbuf->raw_length = len;
    memcpy(pLogbuf->data, group_list_buf, len);
    free(group_list_buf);

    int i = 0;
    for (; i < log_count; ++i)
    {
        cls__log__free_unpacked(pcls_log[i],NULL);
    }
    free(pcls_log);
    free(loggroups[0]);
    free(loggroups);
    return pLogbuf;
}

cls_lz4_content *ClsSerializeWithlz4(cls_log_group_builder *bder)
{

    cls_log_buffer *log = &(bder->grp->logs);
    int log_count =bder->grp->logs_count;
    Cls__Log **pcls_log = (Cls__Log **)malloc(sizeof(Cls__Log *) * bder->grp->logs_count);
    uint8_t *data = log->buffer;
    for (int i = 0; i < bder->grp->logs_count; ++i)
    {
        pcls_log[i] = cls__log__unpack(NULL, (log->buf_index)[i], data);
        data += (log->buf_index)[i];
        if (pcls_log[i] == NULL)
        {
            return NULL;
        }
    }

    Cls__LogGroupList pbLogGroup = CLS__LOG_GROUP_LIST__INIT;
    Cls__LogGroup **loggroups = malloc(sizeof(Cls__LogGroup *));
    loggroups[0] = malloc(sizeof(Cls__LogGroup));
    cls__log_group__init(loggroups[0]);
    loggroups[0]->logs_count = bder->grp->logs_count;;
    loggroups[0]->logs = pcls_log;
    if (bder->grp != NULL && bder->grp->source != NULL){
        loggroups[0]->source = bder->grp->source;
    }
    pbLogGroup.loggrouplist = loggroups;
    pbLogGroup.n_loggrouplist = 1;
    unsigned len = cls__log_group_list__get_packed_size(&pbLogGroup);
    void *group_list_buf = malloc(len);
    cls__log_group_list__pack(&pbLogGroup, group_list_buf);

    if (log->max_buffer_len < bder->loggroup_size)
    {
        _adjust_cls_buffer(log, bder->loggroup_size - log->now_buffer_len);
    }

    int compress_bound = LZ4_compressBound(len);
    char *compress_data = (char *)malloc(compress_bound);
    int compressed_size = LZ4_compress_default(group_list_buf, compress_data, len, compress_bound);
    if (compressed_size <= 0)
    {
        free(compress_data);
        return NULL;
    }
    cls_lz4_content *pLogbuf = (cls_lz4_content *)malloc(sizeof(cls_lz4_content) + compressed_size);
    pLogbuf->length = compressed_size;
    pLogbuf->raw_length = len;
    memcpy(pLogbuf->data, compress_data, compressed_size);
    free(compress_data);
    free(group_list_buf);

    int i = 0;
    for (; i < log_count; ++i)
    {
        cls__log__free_unpacked(pcls_log[i],NULL);
    }
    free(pcls_log);
    free(loggroups[0]);
    free(loggroups);


    return pLogbuf;
}



void ClsFreeLogBuf(cls_lz4_content *pBuf)
{
    free(pBuf);
}

#ifdef CLS_LOG_KEY_VALUE_FLAG

void InnerAddClsLog(cls_log_group_builder *bder, int64_t logTime,
                        int32_t pair_count, char **keys, int32_t *key_lens,
                        char **values, int32_t *val_lens)
{
    

    Cls__Log cls_log = CLS__LOG__INIT;
    Cls__Log__Content **content = malloc(sizeof(Cls__Log__Content *) * pair_count);
    int i = 0;
    for (; i < pair_count; ++i)
    {
        content[i] = malloc(sizeof(Cls__Log__Content));
        cls__log__content__init(content[i]);
        content[i]->key = keys[i];
        content[i]->value = values[i];
    }
    cls_log.n_contents = pair_count;
    cls_log.contents = content;
    cls_log.time = logTime;
    if(cls_log.time == 0){
        struct timeval t;
        gettimeofday(&t, 0);
        cls_log.time = (long)((long)t.tv_sec * 1000 + t.tv_usec/1000);
    }
    //序列化
    unsigned len = cls__log__get_packed_size(&cls_log);
    void *logs_buf = malloc(len);
    memset(logs_buf, 0, len);
    size_t logSize = cls__log__pack(&cls_log, logs_buf); //数据序列化到logs_buf中

    int32_t totalBufferSize = logSize;

    cls_log_buffer *log = &(bder->grp->logs);

    if (log->now_buffer == NULL || log->max_buffer_len < log->now_buffer_len + totalBufferSize)
    {
        _adjust_cls_buffer(log, totalBufferSize);
    }

    bder->loggroup_size += totalBufferSize;
    uint8_t *buf = (uint8_t *)log->now_buffer;
    memcpy(buf, logs_buf, logSize);
    buf += logSize;

    assert(buf - (uint8_t *)log->now_buffer == totalBufferSize);
    log->buf_index[bder->grp->logs_count++] = totalBufferSize;
    log->now_buffer_len += totalBufferSize;
    log->now_buffer = (char *)buf;

    //释放内存
    free(logs_buf);
    i = 0;
    for (; i < pair_count; ++i)
    {
        free(content[i]);
    }
    free(content);
}


#endif
