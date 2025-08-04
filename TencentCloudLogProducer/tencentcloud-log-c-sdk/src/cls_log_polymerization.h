
#ifndef CLS_LOG_POLYMERIZATION_H
#define CLS_LOG_POLYMERIZATION_H

#include <stdint.h>
#include <stdlib.h>
#include <time.h>

#include "cls_log_define.h"
#define CLS_LOG_KEY_VALUE_FLAG

CLS_LOG_CPP_START

typedef struct {
  char *buffer;
  char *now_buffer;
  uint32_t max_buffer_len;
  uint32_t now_buffer_len;
    int *buf_index;
} cls_log_buffer;

typedef struct {
  char *source;
  char *topic;
  cls_log_buffer tags;
  cls_log_buffer logs;
  size_t logs_count;
#ifdef CLS_LOG_KEY_VALUE_FLAG
  char *log_now_buffer;
#endif
} cls_log_group;

typedef struct {
  size_t length;
  size_t raw_length;
  unsigned char data[0];
} cls_lz4_content;

typedef struct {
  cls_log_group *grp;
  size_t loggroup_size;
  void *private_value;
  uint32_t create_time;
} cls_log_group_builder;

extern cls_lz4_content *
ClsSerializeWithlz4(cls_log_group_builder *bder);
extern cls_lz4_content *
ClsSerializeWithNolz4(cls_log_group_builder *bder);
extern void ClsFreeLogBuf(cls_lz4_content *pBuf);
extern cls_log_group_builder *GenerateClsLogGroup();
extern void cls_log_group_destroy(cls_log_group_builder *bder);
extern void InnerAddClsLog(cls_log_group_builder *bder, int64_t logTime,
                               int32_t pair_count, char **keys,
                               int32_t *key_lens, char **values,
                               int32_t *val_lens);
extern void AddClsSource(cls_log_group_builder *bder, const char *src, size_t len);
extern void AddClsTopic(cls_log_group_builder *bder, const char *tpc, size_t len);
extern void AddClsTag(cls_log_group_builder *bder, const char *k, size_t k_len,
                    const char *v, size_t v_len);
extern void AddClsPackageId(cls_log_group_builder *bder, const char *pack,
                        size_t pack_len, size_t packNum);

CLS_LOG_CPP_END
#endif  // CLS_LOG_POLYMERIZATION_H
