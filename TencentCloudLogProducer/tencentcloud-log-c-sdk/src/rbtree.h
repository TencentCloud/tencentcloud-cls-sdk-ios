#ifndef LOG_IOS_SDK_LOG_RBTREE_H
#define LOG_IOS_SDK_LOG_RBTREE_H

#if defined(container_of)
  #undef container_of
  #define container_of(ptr, type, member) ({            \
        const typeof( ((type *)0)->member ) *__mptr = (ptr);    \
        (type *)( (char *)__mptr - offsetof(type,member) );})
#else
  #define container_of(ptr, type, member) ({            \
        const typeof( ((type *)0)->member ) *__mptr = (ptr);    \
        (type *)( (char *)__mptr - offsetof(type,member) );})
#endif

#if defined(offsetof)
  #undef offsetof
  #define offsetof(TYPE, MEMBER) ((size_t) &((TYPE *)0)->MEMBER)
#else
  #define offsetof(TYPE, MEMBER) ((size_t) &((TYPE *)0)->MEMBER)
#endif

#undef NULL
#if defined(__cplusplus)
  #define NULL 0
#else
  #define NULL ((void *)0)
#endif

struct sdk_rb_node
{
    unsigned long  rb_parent_color;
#define    RB_RED        0
#define    RB_BLACK    1
    struct sdk_rb_node *rb_right;
    struct sdk_rb_node *rb_left;
} __attribute__((aligned(sizeof(long))));
    /* The alignment might seem pointless, but allegedly CRIS needs it */

struct sdk_rb_root
{
    struct sdk_rb_node *sdk_rb_node;
};


#define rb_parent(r)   ((struct sdk_rb_node *)((r)->rb_parent_color & ~3))
#define rb_color(r)   ((r)->rb_parent_color & 1)
#define rb_is_red(r)   (!rb_color(r))
#define rb_is_black(r) rb_color(r)
#define rb_set_red(r)  do { (r)->rb_parent_color &= ~1; } while (0)
#define rb_set_black(r)  do { (r)->rb_parent_color |= 1; } while (0)

static inline void rb_set_parent(struct sdk_rb_node *rb, struct sdk_rb_node *p)
{
    rb->rb_parent_color = (rb->rb_parent_color & 3) | (unsigned long)p;
}
static inline void rb_set_color(struct sdk_rb_node *rb, int color)
{
    rb->rb_parent_color = (rb->rb_parent_color & ~1) | color;
}

#define RB_ROOT    (struct sdk_rb_root) { NULL, }
#define    rb_entry(ptr, type, member) container_of(ptr, type, member)

#define RB_EMPTY_ROOT(root)    ((root)->sdk_rb_node == NULL)
#define RB_EMPTY_NODE(node)    (rb_parent(node) == node)
#define RB_CLEAR_NODE(node)    (rb_set_parent(node, node))

static inline void rb_init_node(struct sdk_rb_node *rb)
{
    rb->rb_parent_color = 0;
    rb->rb_right = NULL;
    rb->rb_left = NULL;
    RB_CLEAR_NODE(rb);
}

extern void rb_insert_color(struct sdk_rb_node *, struct sdk_rb_root *);
extern void rb_erase(struct sdk_rb_node *, struct sdk_rb_root *);

typedef void (*rb_augment_f)(struct sdk_rb_node *node, void *data);

extern void rb_augment_insert(struct sdk_rb_node *node,
                  rb_augment_f func, void *data);
extern struct sdk_rb_node *rb_augment_erase_begin(struct sdk_rb_node *node);
extern void rb_augment_erase_end(struct sdk_rb_node *node,
                 rb_augment_f func, void *data);

/* Find logical next and previous nodes in a tree */
extern struct sdk_rb_node *rb_next(const struct sdk_rb_node *);
extern struct sdk_rb_node *rb_prev(const struct sdk_rb_node *);
extern struct sdk_rb_node *rb_first(const struct sdk_rb_root *);
extern struct sdk_rb_node *rb_last(const struct sdk_rb_root *);

/* Fast replacement of a single node without remove/rebalance/add/rebalance */
extern void rb_replace_node(struct sdk_rb_node *victim, struct sdk_rb_node *new,
                            struct sdk_rb_root *root);

static inline void rb_link_node(struct sdk_rb_node * node, struct sdk_rb_node * parent,
                struct sdk_rb_node ** rb_link)
{
    node->rb_parent_color = (unsigned long )parent;
    node->rb_left = node->rb_right = NULL;

    *rb_link = node;
}

#endif    /* _LINUX_RBTREE_H */



