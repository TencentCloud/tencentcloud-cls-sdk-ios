#ifndef LOG_IOS_SDK_LOG_MAP_H
#define LOG_IOS_SDK_LOG_MAP_H

#include "cls_rbtree.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

struct map {
    struct sdk_rb_node node;
    char *key;
    char *val;
};

typedef struct map map_t;
typedef struct sdk_rb_root root_t;
typedef struct sdk_rb_node rb_node_t;

map_t *get(root_t *root, char *str);

map_t *map_first(root_t *tree);

map_t *map_next(rb_node_t *node);

void map_free(map_t *node);

int put(root_t *root, char *key, char *val);

#endif  //_MAP_H

/* vim: set ts=4 sw=4 sts=4 tw=100 */


