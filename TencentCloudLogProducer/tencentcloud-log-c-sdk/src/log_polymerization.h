
#ifndef LOG_BUILDER_H
#define LOG_BUILDER_H

#include <stdint.h>
#include <stdlib.h>
#include <time.h>

#include "log_define.h"
#define LOG_KEY_VALUE_FLAG

CLS_LOG_CPP_START

typedef struct {
  char *buffer;
  char *now_buffer;
  uint32_t max_buffer_len;
  uint32_t now_buffer_len;
    int *buf_index;
} log_buffer;

typedef struct {
  char *source;
  char *topic;
  log_buffer tags;
  log_buffer logs;
  size_t logs_count;
#ifdef LOG_KEY_VALUE_FLAG
  char *log_now_buffer;
#endif
} log_group;

typedef struct {
  size_t length;
  size_t raw_length;
  unsigned char data[0];
} lz4_content;

typedef struct {
  log_group *grp;
  size_t loggroup_size;
  void *private_value;
  uint32_t create_time;
} log_group_builder;

typedef struct {
  char *buffer;
  uint32_t n_buffer;
} log_buf;

extern lz4_content *
SerializeWithlz4(log_group_builder *bder);
extern lz4_content *
SerializeWithNolz4(log_group_builder *bder);
extern void FreeLogBuf(lz4_content *pBuf);
extern log_group_builder *GenerateLogGroup();
extern void log_group_destroy(log_group_builder *bder);
extern void InnerAddLog(log_group_builder *bder, int64_t logTime,
                               int32_t pair_count, char **keys,
                               int32_t *key_lens, char **values,
                               int32_t *val_lens);
extern void AddSource(log_group_builder *bder, const char *src, size_t len);
extern void AddTopic(log_group_builder *bder, const char *tpc, size_t len);
extern void AddTag(log_group_builder *bder, const char *k, size_t k_len,
                    const char *v, size_t v_len);
extern void AddPackageId(log_group_builder *bder, const char *pack,
                        size_t pack_len, size_t packNum);

CLS_LOG_CPP_END
#endif /* log_builder_h */
