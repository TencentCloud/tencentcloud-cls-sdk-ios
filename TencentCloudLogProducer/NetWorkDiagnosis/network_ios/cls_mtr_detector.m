//
//  cls_mtr_detector.m
//  network_ios
//
//  MTR 网络路径探测器 - 使用 BSD socket    
//  支持 ICMP、UDP 和 TCP 三种协议
//

#import "cls_mtr_detector.h"
#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <netinet/ip.h>
#import <netinet/ip_icmp.h>
#import <netinet/tcp.h>
#import <netinet/udp.h>
#import <pthread.h>
#import <sys/time.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>
#import <stdlib.h>
#import <stdarg.h>
#import <math.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <fcntl.h>
#import <netdb.h>
// iOS/macOS 兼容性定义
#if defined(__APPLE__) || defined(__MACH__)
// iOS/macOS 上 struct sock_extended_err 不存在，定义兼容结构体
#ifndef _SOCK_EXTENDED_ERR_DEFINED
#define _SOCK_EXTENDED_ERR_DEFINED
struct sock_extended_err {
    uint32_t ee_errno;
    uint8_t ee_origin;
    uint8_t ee_type;
    uint8_t ee_code;
    uint8_t ee_pad;
    uint32_t ee_info;
    uint32_t ee_data;
};

#ifndef SO_EE_ORIGIN_NONE
#define SO_EE_ORIGIN_NONE 0
#endif
#ifndef SO_EE_ORIGIN_LOCAL
#define SO_EE_ORIGIN_LOCAL 1
#endif
#ifndef SO_EE_ORIGIN_ICMP
#define SO_EE_ORIGIN_ICMP 2
#endif
#ifndef SO_EE_ORIGIN_ICMP6
#define SO_EE_ORIGIN_ICMP6 3
#endif
#endif

// iOS/macOS 上 MSG_ERRQUEUE 标志不存在，定义兼容值
#ifndef MSG_ERRQUEUE
#define MSG_ERRQUEUE 0x2000
#endif

// iOS/macOS 上 IP_RECVERR 和 IPV6_RECVERR 可能不支持
#ifndef IP_RECVERR
#define IP_RECVERR 0
#endif
#ifndef IPV6_RECVERR
#define IPV6_RECVERR 0
#endif
#endif

// Socket 类型定义
typedef int socket_t;
#define INVALID_SOCKET_VALUE -1

// 常量定义
#define MTR_DEFAULT_MAX_TTL 30
#define MTR_DEFAULT_TIMEOUT_MS 2000
#define MTR_DEFAULT_TIMES 10
#define MTR_MAX_PROBES_PER_HOP 30
#define MTR_SRC_PORT_BASE 33434
#define MTR_DST_PORT_BASE 33434
#define MTR_TCP_DST_PORT 80
#define MTR_RECV_BUFFER_SIZE 4096
#define MAX_CONSECUTIVE_TIMEOUTS 5
// 事件队列容量（最小值）：默认 times=10,max_ttl=30 时潜在事件可达 300+
// 旧实现为固定数组 + 满了丢最老事件，容易系统性扭曲统计（loss/latency/stddev/IP 选择）。
// 新实现为“动态环形队列”，初始容量至少为该值，必要时自动扩容，不再主动丢事件。
#define MTR_EVENT_QUEUE_MIN_CAPACITY 1024
#define MTR_EVENT_QUEUE_MAX_CAPACITY 65536
// 探测发送节奏：过慢会显著拉长一次 MTR；过快可能引发拥塞/丢包
// 这里取 30ms 作为折中（不再使用仅为抓包而设置的 50/100ms）
#define MTR_PROBE_GAP_US 30000
// 目标已到达（最终一跳）后：部分主机会对 ICMP Echo Reply 做 rate-limit，
// 为了让最后一跳的 responseNum 更稳定，剩余 probe 放慢节奏
#define MTR_TARGET_PROBE_GAP_US 50000
// TCP 探测：send_tcp_syn 内部会额外 sleep（确保 SYN 发出），因此超时估算使用更保守的 gap
#define MTR_TCP_PROBE_GAP_US 50000
// TCP 探测：send_tcp_syn 内部固定额外等待（确保 SYN 发出）
#define MTR_TCP_SEND_OVERHEAD_US 20000
// 主循环空转睡眠，避免 busy loop 同时提高消费事件速率
#define MTR_MAIN_LOOP_SLEEP_US 10000

// 前向声明
static socket_t create_socket(const char *protocol, int is_ipv6, unsigned int interface_index, int *out_bind_failed, int *out_errno);
static int udp_probe_decode_from_dst_port(uint16_t dst_port, uint16_t base, int *ttl_out, int *probe_index_out);
static int parse_icmp_embedded_udp_ports(const char *buffer, size_t buffer_len, int is_ipv6,
                                        uint8_t *icmp_type_out, uint8_t *icmp_code_out,
                                        uint16_t *orig_src_port_out, uint16_t *orig_dst_port_out);

// ICMP 包结构（iOS/macOS 兼容）
struct IcmpPacket {
    uint8_t type;
    uint8_t code;
    uint16_t checksum;
    uint16_t id;
    uint16_t sequence;
    uint64_t timestamp;
    char data[32];
};

// 辅助函数：获取当前时间戳（毫秒）
static uint64_t get_current_timestamp_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000 + (uint64_t)tv.tv_usec / 1000;
}

// 辅助函数：安全字符串复制
static int safe_strncpy(char *dest, const char *src, size_t dest_size) {
    if (!dest || !src || dest_size == 0) return -1;
    strncpy(dest, src, dest_size - 1);
    dest[dest_size - 1] = '\0';
    return 0;
}

// 计算并行 MTR 的 session 全局超时（毫秒）
// 设计目标：
// - 不能像 timeout_ms*2 那样过早退出（会导致只探测到前几跳就“成功”返回）
// - 也不能无限等待（防止逻辑 bug 导致死循环）
// - 上限由 max_ttl/times/timeout_ms/发送间隔共同决定
static uint64_t mtr_compute_parallel_session_timeout_ms(int max_ttl, int times, int timeout_ms, uint32_t probe_gap_us) {
    if (max_ttl < 1) max_ttl = 1;
    if (times < 1) times = 1;
    if (timeout_ms < 1) timeout_ms = 1;
    if (probe_gap_us == 0) probe_gap_us = 1;
    
    // 发送阶段上界：按当前实现的发送节奏（TTL 顺序 + 每 probe gap）估算
    uint64_t send_phase_ms = ((uint64_t)max_ttl * (uint64_t)times * (uint64_t)probe_gap_us + 999) / 1000;
    // 接收阶段：最后一个 probe 发出后，最多再等待 timeout_ms
    uint64_t recv_phase_ms = (uint64_t)timeout_ms;
    // 额外余量（调度/唤醒/队列消费/系统限速导致的响应延后）
    // 这里取更保守的值，避免“最后一跳”回包来不及入队/消费就提前退出
    uint64_t margin_ms = 2000;
    
    // 最小值：至少给 2*timeout_ms（兼容小 TTL/小 times 的场景）
    uint64_t min_ms = (uint64_t)timeout_ms * 2;
    uint64_t total = send_phase_ms + recv_phase_ms + margin_ms;
    if (total < min_ms) total = min_ms;
    return total;
}

// errno -> 统一错误码（让上层能区分权限/网络策略/资源耗尽/参数问题等）
static cls_mtr_detector_error_code mtr_error_code_from_errno(int e) {
    if (e == 0) return cls_mtr_detector_error_unknown_error;
    switch (e) {
        case EPERM:
        case EACCES:
            return cls_mtr_detector_error_permission_denied;
        case ENETUNREACH:
        case ENETDOWN:
        case ENETRESET:
            return cls_mtr_detector_error_network_unreachable;
        case EHOSTUNREACH:
            return cls_mtr_detector_error_host_unreachable;
        case ETIMEDOUT:
            return cls_mtr_detector_error_timeout;
        case EADDRNOTAVAIL:
            return cls_mtr_detector_error_address_not_available;
        case EADDRINUSE:
            return cls_mtr_detector_error_address_in_use;
        case ENOBUFS:
        case ENOMEM:
        case EMFILE:
        case ENFILE:
            return cls_mtr_detector_error_resource_exhausted;
        default:
            return cls_mtr_detector_error_unknown_error;
    }
}

static const char *mtr_error_name(cls_mtr_detector_error_code code) {
    switch (code) {
        case cls_mtr_detector_error_success: return "success";
        case cls_mtr_detector_error_invalid_target: return "invalid_target";
        case cls_mtr_detector_error_network_unreachable: return "network_unreachable";
        case cls_mtr_detector_error_timeout: return "timeout";
        case cls_mtr_detector_error_permission_denied: return "permission_denied";
        case cls_mtr_detector_error_socket_create_error: return "socket_create_error";
        case cls_mtr_detector_error_resolve_error: return "resolve_error";
        case cls_mtr_detector_error_net_binding_failed: return "net_binding_failed";
        case cls_mtr_detector_error_invalid_param: return "invalid_param";
        case cls_mtr_detector_error_setsockopt_failed: return "setsockopt_failed";
        case cls_mtr_detector_error_send_failed: return "send_failed";
        case cls_mtr_detector_error_recv_failed: return "recv_failed";
        case cls_mtr_detector_error_connect_failed: return "connect_failed";
        case cls_mtr_detector_error_host_unreachable: return "host_unreachable";
        case cls_mtr_detector_error_resource_exhausted: return "resource_exhausted";
        case cls_mtr_detector_error_address_not_available: return "address_not_available";
        case cls_mtr_detector_error_address_in_use: return "address_in_use";
        case cls_mtr_detector_error_unknown_error: default: return "unknown_error";
    }
}

static cls_mtr_detector_error_code mtr_classify_syscall_failure(const char *op, int e) {
    cls_mtr_detector_error_code base = mtr_error_code_from_errno(e);
    if (!op) return base;
    // 对“操作类型”做更细分（比单纯 errno 更可解释）
    if (strcmp(op, "setsockopt") == 0) return (base == cls_mtr_detector_error_unknown_error) ? cls_mtr_detector_error_setsockopt_failed : base;
    if (strcmp(op, "sendto") == 0 || strcmp(op, "send") == 0) return (base == cls_mtr_detector_error_unknown_error) ? cls_mtr_detector_error_send_failed : base;
    if (strcmp(op, "recvfrom") == 0 || strcmp(op, "recvmsg") == 0 || strcmp(op, "select") == 0 || strcmp(op, "recv") == 0) return (base == cls_mtr_detector_error_unknown_error) ? cls_mtr_detector_error_recv_failed : base;
    if (strcmp(op, "connect") == 0) return (base == cls_mtr_detector_error_unknown_error) ? cls_mtr_detector_error_connect_failed : base;
    return base;
}

static void mtr_record_fatal_error(cls_mtr_path_result *path, const char *op, int e) {
    if (!path) return;
    path->last_errno = e;
    if (op && op[0] != '\0') {
        safe_strncpy(path->last_error_op, op, sizeof(path->last_error_op));
    } else {
        path->last_error_op[0] = '\0';
    }
}

// 辅助函数：计算 ICMP 校验和
static uint16_t calculate_icmp_checksum(const void *data, size_t len) {
    if (!data || len == 0) return 0;
    
    const uint16_t *buf = (const uint16_t *)data;
    uint32_t sum = 0;
    size_t word_count = len / 2;
    
    for (size_t i = 0; i < word_count; i++) {
        sum += buf[i];
    }
    
    if (len & 1) {
        sum += ((const uint8_t *)buf)[word_count * 2] << 8;
    }
    
    while (sum >> 16) {
        sum = (sum & 0xFFFF) + (sum >> 16);
    }
    
    return (uint16_t)(~sum);
}

// 辅助函数：解析主机名到 IP 地址
static int resolve_hostname(const char *hostname, int prefer, char *ip_buffer) {
    if (!hostname || !ip_buffer) return -1;
    
    struct addrinfo hints, *result = NULL;
    memset(&hints, 0, sizeof(hints));
    
    if (prefer == 2) {
        hints.ai_family = AF_INET;
    } else if (prefer == 3) {
        hints.ai_family = AF_INET6;
    } else {
        hints.ai_family = AF_UNSPEC;
    }
    
    int ret = getaddrinfo(hostname, NULL, &hints, &result);
    if (ret != 0 || !result) {
        return -1;
    }
    
    // 根据偏好选择地址
    struct addrinfo *ipv4_result = NULL;
    struct addrinfo *ipv6_result = NULL;
    
    for (struct addrinfo *p = result; p != NULL; p = p->ai_next) {
        if (p->ai_family == AF_INET && !ipv4_result) {
            ipv4_result = p;
        } else if (p->ai_family == AF_INET6 && !ipv6_result) {
            ipv6_result = p;
        }
    }
    
    struct addrinfo *selected = NULL;
    if (prefer == 1 || prefer == 3) {
        selected = ipv6_result ? ipv6_result : (prefer == 3 ? NULL : ipv4_result);
    } else {
        selected = ipv4_result ? ipv4_result : (prefer == 2 ? NULL : ipv6_result);
    }
    
    if (!selected) {
        freeaddrinfo(result);
        return -1;
    }
    
    int ntop_result = 0;
    if (selected->ai_family == AF_INET) {
        struct sockaddr_in *addr_in = (struct sockaddr_in *)selected->ai_addr;
        ntop_result = (inet_ntop(AF_INET, &addr_in->sin_addr, ip_buffer, INET6_ADDRSTRLEN) != NULL) ? 0 : -1;
    } else if (selected->ai_family == AF_INET6) {
        struct sockaddr_in6 *addr_in6 = (struct sockaddr_in6 *)selected->ai_addr;
        ntop_result = (inet_ntop(AF_INET6, &addr_in6->sin6_addr, ip_buffer, INET6_ADDRSTRLEN) != NULL) ? 0 : -1;
    } else {
        ntop_result = -1;
    }
    
    freeaddrinfo(result);
    return ntop_result;
}

// 初始化路径结果
static void init_path_result(cls_mtr_path_result *path, const char *target, const char *protocol, const char *host_ip) {
    if (!path) return;
    memset(path, 0, sizeof(cls_mtr_path_result));
    safe_strncpy(path->method, "mtr", sizeof(path->method));
    safe_strncpy(path->host, target ? target : "", sizeof(path->host));
    safe_strncpy(path->host_ip, host_ip ? host_ip : "", sizeof(path->host_ip));
    safe_strncpy(path->protocol, protocol ? protocol : "", sizeof(path->protocol));
    path->timestamp = get_current_timestamp_ms();
    path->results = NULL;
    path->results_count = 0;
    path->results_capacity = 0;
    path->last_errno = 0;
    path->last_error_op[0] = '\0';
}

// 扩展路径结果数组
static int expand_path_results(cls_mtr_path_result *path, size_t new_capacity) {
    if (!path || new_capacity <= path->results_capacity) return 0;
    
    cls_mtr_hop_result *new_results = realloc(path->results, new_capacity * sizeof(cls_mtr_hop_result));
    if (!new_results) return -1;
    
    // 初始化新分配的内存
    memset(new_results + path->results_capacity, 0, 
           (new_capacity - path->results_capacity) * sizeof(cls_mtr_hop_result));
    
    path->results = new_results;
    path->results_capacity = new_capacity;
    return 0;
}

// 确保路径结果数组有足够的容量
static int ensure_path_results_capacity(cls_mtr_path_result *path, size_t required_count) {
    if (!path) return -1;
    
    if (required_count > path->results_capacity) {
        size_t new_capacity = path->results_capacity == 0 ? 32 : path->results_capacity * 2;
        while (new_capacity < required_count) {
            new_capacity *= 2;
        }
        if (expand_path_results(path, new_capacity) != 0) {
            return -1;
        }
    }
    
    if (required_count > path->results_count) {
        path->results_count = required_count;
    }
    
    return 0;
}

// 初始化跳结果
static void init_hop_result(cls_mtr_hop_result *hop, int hop_number) {
    if (!hop) return;
    memset(hop, 0, sizeof(cls_mtr_hop_result));
    hop->hop = hop_number;
    safe_strncpy(hop->ip, "*", sizeof(hop->ip));
    // loss 单位为百分比，与头文件注释保持一致
    hop->loss = 1.0;
    hop->latency = 0.0;
    hop->latency_min = 0.0;
    hop->latency_max = 0.0;
    hop->stddev = 0.0;
    hop->responseNum = 0;
}

// 前置声明：ICMP 收包函数，供接收线程使用
static int receive_icmp_response(socket_t sock, int timeout_ms, const char *target_ip,
                                 int ttl, int is_ipv6, double *rtt_out, char *src_ip_out,
                                 uint64_t send_time, uint16_t expected_id);

// 前置声明：解析 ICMP 响应
static int parse_icmp_response(const char *buffer, size_t buffer_len, int is_ipv6,
                                int *original_ttl, int *original_seq, int *is_echo_reply,
                                uint16_t *icmp_identifier);

// ICMP 头部结构（iOS/macOS 兼容）
// 注意：使用不同的名称避免与系统定义冲突
struct mtr_icmphdr {
    uint8_t type;
    uint8_t code;
    uint16_t checksum;
    union {
        struct {
            uint16_t id;
            uint16_t sequence;
        } echo;
        uint32_t gateway;
    } un;
};

// ICMP 并行探测：事件队列结构
typedef struct {
    int ttl;                              // 探测的 TTL
    int probe_index;                      // 第几次探测（0-based）
    uint64_t recv_time;                   // 接收时间戳
    char src_ip[INET6_ADDRSTRLEN];        // 源 IP
    int is_echo_reply;                    // 是否为 Echo Reply
} mtr_icmp_event;

// 线程安全的事件队列
typedef struct {
    mtr_icmp_event *events;               // 动态环形缓冲区
    int head;
    int tail;
    int count;
    int capacity;
    uint64_t dropped;                     // 扩容失败时的兜底丢弃计数
    pthread_mutex_t mutex;
} mtr_event_queue;

// 每个 hop 的状态
typedef struct {
    uint64_t send_times[MTR_MAX_PROBES_PER_HOP];  // 每次探测的发送时间
    double rtts[MTR_MAX_PROBES_PER_HOP];           // 每次探测的 RTT
    char src_ips[MTR_MAX_PROBES_PER_HOP][INET6_ADDRSTRLEN];  // 每次探测的源 IP
    int sent_count;                                 // 已发送的探测数
    int recv_count;                                 // 已接收的响应数
    int ttl_done;                                   // 该 TTL 是否完成（到达目标或超时）
    uint64_t first_send_time;                       // 第一次发送时间
} mtr_hop_state;

// 为 hop 状态按 max_ttl 动态分配（1-indexed）
static mtr_hop_state *mtr_alloc_hops_for_max_ttl(int max_ttl) {
    if (max_ttl < 1) return NULL;
    size_t count = (size_t)max_ttl + 1; // 预留 0 号位，ttl 从 1 开始
    return (mtr_hop_state *)calloc(count, sizeof(mtr_hop_state));
}

// 从 hop 状态生成最终输出（ICMP/UDP/TCP 复用）
static void fill_hop_result_from_state(cls_mtr_hop_result *hop_result,
                                       const mtr_hop_state *hop_state,
                                       int ttl,
                                       int times) {
    if (!hop_result) return;
    init_hop_result(hop_result, ttl);
    if (!hop_state || times <= 0) return;
    
    const int recv_count = hop_state->recv_count;
    if (recv_count <= 0) {
        hop_result->loss = 1.0;
        return;
    }
    
    // 计算 RTT 统计（只统计 rtt>0 的样本，避免 rtts 与 recv_count 不一致导致除零/偏差）
    double sum = 0.0;
    double min_rtt = 0.0;
    double max_rtt = 0.0;
    int valid_rtt_count = 0;
    for (int i = 0; i < times; i++) {
        double rtt = hop_state->rtts[i];
        if (rtt > 0.0) {
            if (valid_rtt_count == 0) {
                min_rtt = rtt;
                max_rtt = rtt;
            } else {
                if (rtt < min_rtt) min_rtt = rtt;
                if (rtt > max_rtt) max_rtt = rtt;
            }
            sum += rtt;
            valid_rtt_count++;
        }
    }
    
    if (valid_rtt_count > 0) {
        const double avg = sum / (double)valid_rtt_count;
        hop_result->latency = avg;
        hop_result->latency_min = min_rtt;
        hop_result->latency_max = max_rtt;
        
        double variance = 0.0;
        for (int i = 0; i < times; i++) {
            double rtt = hop_state->rtts[i];
            if (rtt > 0.0) {
                double diff = rtt - avg;
                variance += diff * diff;
            }
        }
        hop_result->stddev = sqrt(variance / (double)valid_rtt_count);
    }
    
    hop_result->responseNum = recv_count;
    // loss 单位为百分比
    hop_result->loss = ((double)(times - recv_count)) / (double)times;
    if (hop_result->loss < 0.0) hop_result->loss = 0.0;
    if (hop_result->loss > 1.0) hop_result->loss = 1.0;
    
    // 选择最常见的 IP（跳过空字符串）
    const char *best_ip = NULL;
    int best_count = 0;
    for (int i = 0; i < times; i++) {
        const char *ip = hop_state->src_ips[i];
        if (!ip || ip[0] == '\0') continue;
        int count = 1;
        for (int j = i + 1; j < times; j++) {
            const char *ip2 = hop_state->src_ips[j];
            if (!ip2 || ip2[0] == '\0') continue;
            if (strcmp(ip, ip2) == 0) count++;
        }
        if (count > best_count) {
            best_count = count;
            best_ip = ip;
        }
    }
    
    if (best_ip && best_ip[0] != '\0') {
        safe_strncpy(hop_result->ip, best_ip, sizeof(hop_result->ip));
    }
}

// 检查“连续 N 个 hop 超时且无响应”并触发提前停止（复用 ICMP/UDP/TCP）
// 返回 1 表示已触发停止；返回 0 表示未触发。
static int mtr_check_consecutive_timeouts_and_stop(mtr_hop_state *hops,
                                                   int max_ttl,
                                                   int times,
                                                   int timeout_ms,
                                                   uint64_t now_ms,
                                                   int limit_ttl,
                                                   cls_mtr_path_result *path,
                                                   const char *log_tag) {
    if (!hops || max_ttl < 1 || times < 1 || timeout_ms < 1 || limit_ttl < 1) return 0;
    if (limit_ttl > max_ttl) limit_ttl = max_ttl;
    
    int consecutive_timeout_count = 0;
    int last_valid_hop = 0;
    int first_timeout_ttl = 0;
    
    for (int ttl = 1; ttl <= limit_ttl; ttl++) {
        mtr_hop_state *hop = &hops[ttl];
        if (hop->sent_count >= times) {
            // 该 hop 已发送完所有探测
            uint64_t hop_elapsed = now_ms - hop->first_send_time;
            if (hop_elapsed > (uint64_t)timeout_ms && hop->recv_count == 0) {
                // 超时且没有收到任何响应
                if (consecutive_timeout_count == 0) {
                    first_timeout_ttl = ttl;
                }
                consecutive_timeout_count++;
                if (consecutive_timeout_count >= MAX_CONSECUTIVE_TIMEOUTS) {
                    // 标记所有后续 TTL 为完成
                    for (int t = ttl; t <= max_ttl; t++) {
                        hops[t].ttl_done = 1;
                    }
                    // 记录最后一个有效 hop
                    if (path && last_valid_hop > 0) {
                        path->lastHop = last_valid_hop;
                    }
                    return 1;
                }
            } else if (hop->recv_count > 0) {
                // 收到响应，重置连续超时计数
                consecutive_timeout_count = 0;
                last_valid_hop = ttl;
                first_timeout_ttl = 0;
            } else {
                // 已发送完但还未超时，重置连续超时计数（因为不连续）
                consecutive_timeout_count = 0;
                first_timeout_ttl = 0;
            }
        }
        // 如果还未发送完，不处理（保持当前的连续超时计数）
    }
    
    return 0;
}

// ICMP 并行探测 session
typedef struct {
    const char *target_ip;
    int is_ipv6;
    int max_ttl;
    int times;
    int timeout_ms;
    socket_t icmp_socket;
    // session 级 token：不依赖 ICMP ID（可能被内核改写），而是对 sequence 做 XOR 编码
    // send: seq_wire = ((ttl<<8)|probe_index) ^ seq_xor_token
    // recv: decoded = seq_wire ^ seq_xor_token -> (ttl, probe_index)
    uint16_t seq_xor_token;
    // 注意：单个 hop 状态体较大（包含 30 次探测的 send_times/rtts/src_ips）。
    // 如果直接在栈上放 hops[256]，在 iOS 上非常容易触发线程栈溢出。
    // 因此 hops 改为按 max_ttl 动态分配（1-indexed，长度 max_ttl+1）。
    mtr_hop_state *hops;
    mtr_event_queue *event_queue;         // 事件队列
    uint64_t session_start_time;           // session 开始时间
    int stop;                              // 停止标志
    int target_reached;                    // 是否已到达目标（收到目标 IP 的响应）
    int target_reached_ttl;                // 到达目标的 TTL
} mtr_icmp_parallel_session;

// UDP 并行探测：事件结构（与 ICMP 类似，但用于 UDP）
typedef struct {
    int ttl;                              // 探测的 TTL
    int probe_index;                      // 第几次探测（0-based）
    uint64_t recv_time;                   // 接收时间戳
    char src_ip[INET6_ADDRSTRLEN];        // 源 IP
    int is_target_reply;                  // 是否为目标的回复（ICMP Port Unreachable 表示到达目标）
} mtr_udp_event;

// UDP 事件队列（复用相同的队列结构）
typedef struct {
    mtr_udp_event *events;                // 动态环形缓冲区
    int head;
    int tail;
    int count;
    int capacity;
    uint64_t dropped;                     // 扩容失败时的兜底丢弃计数
    pthread_mutex_t mutex;
} mtr_udp_event_queue;

// UDP 并行探测 session
typedef struct {
    const char *target_ip;
    int is_ipv6;
    int max_ttl;
    int times;
    int timeout_ms;
    socket_t udp_socket;
    socket_t icmp_socket;                 // 用于接收 ICMP 错误消息
    mtr_hop_state *hops;
    mtr_udp_event_queue *event_queue;
    uint64_t session_start_time;
    int stop;
    int target_reached;
    int target_reached_ttl;
} mtr_udp_parallel_session;

// TCP 并行探测：事件结构
typedef struct {
    int ttl;                              // 探测的 TTL
    int probe_index;                      // 第几次探测（0-based）
    uint64_t recv_time;                   // 接收时间戳
    char src_ip[INET6_ADDRSTRLEN];        // 源 IP
    int is_target_reply;                  // 是否为目标的直接回复（TCP SYN-ACK）
} mtr_tcp_event;

// TCP 事件队列
typedef struct {
    mtr_tcp_event *events;                // 动态环形缓冲区
    int head;
    int tail;
    int count;
    int capacity;
    uint64_t dropped;                     // 扩容失败时的兜底丢弃计数
    pthread_mutex_t mutex;
} mtr_tcp_event_queue;

// TCP 并行探测 session
typedef struct {
    const char *target_ip;
    int is_ipv6;
    int max_ttl;
    int times;
    int timeout_ms;
    socket_t *tcp_sockets;                // TCP socket 数组
    int tcp_socket_count;                 // socket 数量
    mtr_hop_state *hops;
    mtr_tcp_event_queue *event_queue;
    uint64_t session_start_time;
    int stop;
    int target_reached;
    int target_reached_ttl;
} mtr_tcp_parallel_session;

// 发送 ICMP Echo 请求
static int send_icmp_echo(socket_t icmp_socket, const char *target_ip, int ttl,
                          int sequence, uint16_t icmp_identifier, uint16_t seq_xor_token,
                          uint64_t *send_time, int *out_errno, const char **out_failed_op) {
    if (!target_ip || icmp_socket < 0 || ttl < 1 || ttl > 255) return -1;
    if (out_errno) *out_errno = 0;
    if (out_failed_op) *out_failed_op = NULL;
    
    int is_ipv6 = (strchr(target_ip, ':') != NULL);
    
    // 构建 ICMP 包
    // 注意：在 iOS/macOS 上使用 SOCK_DGRAM 时，内核会自动管理 ICMP ID
    // 应用程序设置的 ID 可能被内核改写，所以这里设置的值可能不会生效
    // 但为了兼容性，仍然设置 ID（内核可能会使用它，也可能不使用）
    struct IcmpPacket icmp_packet;
    memset(&icmp_packet, 0, sizeof(icmp_packet));
    icmp_packet.type = is_ipv6 ? 128 : 8; // ICMP6_ECHO_REQUEST : ICMP_ECHO
    icmp_packet.code = 0;
    icmp_packet.id = icmp_identifier;  // 可能被内核改写
    // 使用 sequence 字段编码 TTL 和 probe_index：
    // sequence = (ttl << 8) | (probe_index & 0xFF)
    // 这样可以从响应中同时提取 TTL 和 probe_index
    // 限制：TTL 最大 255，probe_index 最大 255（足够使用）
    // 同时引入 session token（XOR），避免把非本次 run 的 ICMP 报文误计入
    uint16_t encoded_seq = (uint16_t)((ttl << 8) | (sequence & 0xFF));
    uint16_t wire_seq = (uint16_t)(encoded_seq ^ seq_xor_token);
    icmp_packet.sequence = htons(wire_seq);
    icmp_packet.timestamp = get_current_timestamp_ms();
    snprintf(icmp_packet.data, sizeof(icmp_packet.data), "MTR-%d-%d", ttl, sequence);
    
    // 计算校验和（仅 IPv4）
    if (!is_ipv6) {
        icmp_packet.checksum = 0;
        icmp_packet.checksum = calculate_icmp_checksum(&icmp_packet, sizeof(icmp_packet));
    }
    
    // 发送
    ssize_t sent = 0;
    if (is_ipv6) {
        struct sockaddr_in6 addr6;
        memset(&addr6, 0, sizeof(addr6));
        addr6.sin6_family = AF_INET6;
        if (inet_pton(AF_INET6, target_ip, &addr6.sin6_addr) != 1) {
            if (out_errno) *out_errno = EINVAL;
            if (out_failed_op) *out_failed_op = "inet_pton";
            return -1;
        }
        sent = sendto(icmp_socket, &icmp_packet, sizeof(icmp_packet), 0, 
                     (struct sockaddr *)&addr6, sizeof(addr6));
    } else {
        struct sockaddr_in addr4;
        memset(&addr4, 0, sizeof(addr4));
        addr4.sin_family = AF_INET;
        if (inet_pton(AF_INET, target_ip, &addr4.sin_addr) != 1) {
            if (out_errno) *out_errno = EINVAL;
            if (out_failed_op) *out_failed_op = "inet_pton";
            return -1;
        }
        sent = sendto(icmp_socket, &icmp_packet, sizeof(icmp_packet), 0, 
                     (struct sockaddr *)&addr4, sizeof(addr4));
    }
    
    if (sent < 0 || sent != (ssize_t)sizeof(icmp_packet)) {
        if (out_errno) *out_errno = errno;
        if (out_failed_op) *out_failed_op = "sendto";
        return -1;
    }
    
    if (send_time) {
        *send_time = get_current_timestamp_ms();
    }
    
    
    return 0;
}

// 事件队列操作函数（动态环形队列，必要时自动扩容，避免丢事件扭曲统计）
static int mtr_compute_event_queue_capacity(int max_ttl, int times) {
    if (max_ttl < 1) max_ttl = 1;
    if (times < 1) times = 1;
    uint64_t expected = (uint64_t)max_ttl * (uint64_t)times;
    // 预留余量：某些网络设备可能产生重复/额外 ICMP 错误
    uint64_t cap = expected * 2;
    if (cap < (uint64_t)MTR_EVENT_QUEUE_MIN_CAPACITY) cap = (uint64_t)MTR_EVENT_QUEUE_MIN_CAPACITY;
    if (cap > (uint64_t)MTR_EVENT_QUEUE_MAX_CAPACITY) cap = (uint64_t)MTR_EVENT_QUEUE_MAX_CAPACITY;
    return (int)cap;
}

static int event_queue_grow_locked(mtr_event_queue *queue, int min_capacity) {
    if (!queue) return -1;
    if (min_capacity < MTR_EVENT_QUEUE_MIN_CAPACITY) min_capacity = MTR_EVENT_QUEUE_MIN_CAPACITY;
    int new_cap = queue->capacity > 0 ? queue->capacity : MTR_EVENT_QUEUE_MIN_CAPACITY;
    while (new_cap < min_capacity && new_cap < MTR_EVENT_QUEUE_MAX_CAPACITY) {
        new_cap *= 2;
    }
    if (new_cap > MTR_EVENT_QUEUE_MAX_CAPACITY) new_cap = MTR_EVENT_QUEUE_MAX_CAPACITY;
    if (new_cap < min_capacity) return -1;

    mtr_icmp_event *new_events = (mtr_icmp_event *)calloc((size_t)new_cap, sizeof(mtr_icmp_event));
    if (!new_events) return -1;

    // 将旧队列内容按顺序拷贝到新队列的 [0..count)
    for (int i = 0; i < queue->count; i++) {
        int idx = (queue->head + i) % queue->capacity;
        new_events[i] = queue->events[idx];
    }

    free(queue->events);
    queue->events = new_events;
    queue->capacity = new_cap;
    queue->head = 0;
    queue->tail = queue->count;
    return 0;
}

static int event_queue_init(mtr_event_queue *queue, int capacity) {
    if (!queue) return -1;
    memset(queue, 0, sizeof(mtr_event_queue));
    if (capacity < MTR_EVENT_QUEUE_MIN_CAPACITY) capacity = MTR_EVENT_QUEUE_MIN_CAPACITY;
    if (capacity > MTR_EVENT_QUEUE_MAX_CAPACITY) capacity = MTR_EVENT_QUEUE_MAX_CAPACITY;
    queue->capacity = capacity;
    queue->events = (mtr_icmp_event *)calloc((size_t)queue->capacity, sizeof(mtr_icmp_event));
    if (!queue->events) return -1;
    pthread_mutex_init(&queue->mutex, NULL);
    return 0;
}

static void event_queue_destroy(mtr_event_queue *queue) {
    if (!queue) return;
    if (queue->events) {
        free(queue->events);
        queue->events = NULL;
    }
    pthread_mutex_destroy(&queue->mutex);
    queue->capacity = 0;
    queue->head = 0;
    queue->tail = 0;
    queue->count = 0;
}

static int event_queue_push(mtr_event_queue *queue, const mtr_icmp_event *event) {
    if (!queue || !event) return -1;
    pthread_mutex_lock(&queue->mutex);

    if (!queue->events || queue->capacity <= 0) {
        pthread_mutex_unlock(&queue->mutex);
        return -1;
    }

    if (queue->count >= queue->capacity) {
        // 优先扩容，避免丢事件导致统计偏差
        if (event_queue_grow_locked(queue, queue->count + 1) != 0) {
            // 扩容失败：兜底保持旧行为（丢最老），并计数
            queue->head = (queue->head + 1) % queue->capacity;
            queue->count--;
            queue->dropped++;
        }
    }

    queue->events[queue->tail] = *event;
    queue->tail = (queue->tail + 1) % queue->capacity;
    queue->count++;
    pthread_mutex_unlock(&queue->mutex);
    return 0;
}

static int event_queue_try_pop(mtr_event_queue *queue, mtr_icmp_event *event) {
    if (!queue || !event) return -1;
    pthread_mutex_lock(&queue->mutex);
    if (queue->count > 0 && queue->events && queue->capacity > 0) {
        *event = queue->events[queue->head];
        queue->head = (queue->head + 1) % queue->capacity;
        queue->count--;
        pthread_mutex_unlock(&queue->mutex);
        return 0;
    }
    pthread_mutex_unlock(&queue->mutex);
    return -1;
}

// UDP 事件队列操作函数（动态环形队列）
static int udp_event_queue_grow_locked(mtr_udp_event_queue *queue, int min_capacity) {
    if (!queue) return -1;
    if (min_capacity < MTR_EVENT_QUEUE_MIN_CAPACITY) min_capacity = MTR_EVENT_QUEUE_MIN_CAPACITY;
    int new_cap = queue->capacity > 0 ? queue->capacity : MTR_EVENT_QUEUE_MIN_CAPACITY;
    while (new_cap < min_capacity && new_cap < MTR_EVENT_QUEUE_MAX_CAPACITY) {
        new_cap *= 2;
    }
    if (new_cap > MTR_EVENT_QUEUE_MAX_CAPACITY) new_cap = MTR_EVENT_QUEUE_MAX_CAPACITY;
    if (new_cap < min_capacity) return -1;

    mtr_udp_event *new_events = (mtr_udp_event *)calloc((size_t)new_cap, sizeof(mtr_udp_event));
    if (!new_events) return -1;
    for (int i = 0; i < queue->count; i++) {
        int idx = (queue->head + i) % queue->capacity;
        new_events[i] = queue->events[idx];
    }
    free(queue->events);
    queue->events = new_events;
    queue->capacity = new_cap;
    queue->head = 0;
    queue->tail = queue->count;
    return 0;
}

static int udp_event_queue_init(mtr_udp_event_queue *queue, int capacity) {
    if (!queue) return -1;
    memset(queue, 0, sizeof(mtr_udp_event_queue));
    if (capacity < MTR_EVENT_QUEUE_MIN_CAPACITY) capacity = MTR_EVENT_QUEUE_MIN_CAPACITY;
    if (capacity > MTR_EVENT_QUEUE_MAX_CAPACITY) capacity = MTR_EVENT_QUEUE_MAX_CAPACITY;
    queue->capacity = capacity;
    queue->events = (mtr_udp_event *)calloc((size_t)queue->capacity, sizeof(mtr_udp_event));
    if (!queue->events) return -1;
    pthread_mutex_init(&queue->mutex, NULL);
    return 0;
}

static void udp_event_queue_destroy(mtr_udp_event_queue *queue) {
    if (!queue) return;
    if (queue->events) {
        free(queue->events);
        queue->events = NULL;
    }
    pthread_mutex_destroy(&queue->mutex);
    queue->capacity = 0;
    queue->head = 0;
    queue->tail = 0;
    queue->count = 0;
}

static int udp_event_queue_push(mtr_udp_event_queue *queue, const mtr_udp_event *event) {
    if (!queue || !event) return -1;
    pthread_mutex_lock(&queue->mutex);
    if (!queue->events || queue->capacity <= 0) {
        pthread_mutex_unlock(&queue->mutex);
        return -1;
    }
    if (queue->count >= queue->capacity) {
        if (udp_event_queue_grow_locked(queue, queue->count + 1) != 0) {
            queue->head = (queue->head + 1) % queue->capacity;
            queue->count--;
            queue->dropped++;
        }
    }
    queue->events[queue->tail] = *event;
    queue->tail = (queue->tail + 1) % queue->capacity;
    queue->count++;
    pthread_mutex_unlock(&queue->mutex);
    return 0;
}

static int udp_event_queue_try_pop(mtr_udp_event_queue *queue, mtr_udp_event *event) {
    if (!queue || !event) return -1;
    pthread_mutex_lock(&queue->mutex);
    if (queue->count > 0 && queue->events && queue->capacity > 0) {
        *event = queue->events[queue->head];
        queue->head = (queue->head + 1) % queue->capacity;
        queue->count--;
        pthread_mutex_unlock(&queue->mutex);
        return 0;
    }
    pthread_mutex_unlock(&queue->mutex);
    return -1;
}

// TCP 事件队列操作函数（动态环形队列）
static int tcp_event_queue_grow_locked(mtr_tcp_event_queue *queue, int min_capacity) {
    if (!queue) return -1;
    if (min_capacity < MTR_EVENT_QUEUE_MIN_CAPACITY) min_capacity = MTR_EVENT_QUEUE_MIN_CAPACITY;
    int new_cap = queue->capacity > 0 ? queue->capacity : MTR_EVENT_QUEUE_MIN_CAPACITY;
    while (new_cap < min_capacity && new_cap < MTR_EVENT_QUEUE_MAX_CAPACITY) {
        new_cap *= 2;
    }
    if (new_cap > MTR_EVENT_QUEUE_MAX_CAPACITY) new_cap = MTR_EVENT_QUEUE_MAX_CAPACITY;
    if (new_cap < min_capacity) return -1;

    mtr_tcp_event *new_events = (mtr_tcp_event *)calloc((size_t)new_cap, sizeof(mtr_tcp_event));
    if (!new_events) return -1;
    for (int i = 0; i < queue->count; i++) {
        int idx = (queue->head + i) % queue->capacity;
        new_events[i] = queue->events[idx];
    }
    free(queue->events);
    queue->events = new_events;
    queue->capacity = new_cap;
    queue->head = 0;
    queue->tail = queue->count;
    return 0;
}

static int tcp_event_queue_init(mtr_tcp_event_queue *queue, int capacity) {
    if (!queue) return -1;
    memset(queue, 0, sizeof(mtr_tcp_event_queue));
    if (capacity < MTR_EVENT_QUEUE_MIN_CAPACITY) capacity = MTR_EVENT_QUEUE_MIN_CAPACITY;
    if (capacity > MTR_EVENT_QUEUE_MAX_CAPACITY) capacity = MTR_EVENT_QUEUE_MAX_CAPACITY;
    queue->capacity = capacity;
    queue->events = (mtr_tcp_event *)calloc((size_t)queue->capacity, sizeof(mtr_tcp_event));
    if (!queue->events) return -1;
    pthread_mutex_init(&queue->mutex, NULL);
    return 0;
}

static void tcp_event_queue_destroy(mtr_tcp_event_queue *queue) {
    if (!queue) return;
    if (queue->events) {
        free(queue->events);
        queue->events = NULL;
    }
    pthread_mutex_destroy(&queue->mutex);
    queue->capacity = 0;
    queue->head = 0;
    queue->tail = 0;
    queue->count = 0;
}

static int tcp_event_queue_push(mtr_tcp_event_queue *queue, const mtr_tcp_event *event) {
    if (!queue || !event) return -1;
    pthread_mutex_lock(&queue->mutex);
    if (!queue->events || queue->capacity <= 0) {
        pthread_mutex_unlock(&queue->mutex);
        return -1;
    }
    if (queue->count >= queue->capacity) {
        if (tcp_event_queue_grow_locked(queue, queue->count + 1) != 0) {
            queue->head = (queue->head + 1) % queue->capacity;
            queue->count--;
            queue->dropped++;
        }
    }
    queue->events[queue->tail] = *event;
    queue->tail = (queue->tail + 1) % queue->capacity;
    queue->count++;
    pthread_mutex_unlock(&queue->mutex);
    return 0;
}

static int tcp_event_queue_try_pop(mtr_tcp_event_queue *queue, mtr_tcp_event *event) {
    if (!queue || !event) return -1;
    pthread_mutex_lock(&queue->mutex);
    if (queue->count > 0 && queue->events && queue->capacity > 0) {
        *event = queue->events[queue->head];
        queue->head = (queue->head + 1) % queue->capacity;
        queue->count--;
        pthread_mutex_unlock(&queue->mutex);
        return 0;
    }
    pthread_mutex_unlock(&queue->mutex);
    return -1;
}

// 并行模式的 ICMP worker（持续收包，推送到事件队列）
typedef struct {
    pthread_t thread;
    pthread_mutex_t mutex;
    int running;
    int stop;
    socket_t sock;
    mtr_event_queue *event_queue;
    int is_ipv6;
    int max_ttl;
    int times;
    uint16_t seq_xor_token; // ICMP session token（见 mtr_icmp_parallel_session）
} icmp_parallel_worker_ctx;

// 并行模式的 worker 线程：持续收包并推送到事件队列
static void *icmp_parallel_worker_thread(void *arg) {
    icmp_parallel_worker_ctx *ctx = (icmp_parallel_worker_ctx *)arg;
    
    char buffer[MTR_RECV_BUFFER_SIZE];
    struct sockaddr_storage from_addr;
    
    while (1) {
        pthread_mutex_lock(&ctx->mutex);
        if (ctx->stop) {
            pthread_mutex_unlock(&ctx->mutex);
            break;
        }
        socket_t sock = ctx->sock;
        mtr_event_queue *queue = ctx->event_queue;
        int is_ipv6 = ctx->is_ipv6;
        int max_ttl = ctx->max_ttl;
        int times = ctx->times;
        uint16_t seq_xor_token = ctx->seq_xor_token;
        pthread_mutex_unlock(&ctx->mutex);
        
        if (sock < 0 || !queue) {
            usleep(10000);  // 10ms
            continue;
        }
        
        // 使用 select 等待数据可读（非阻塞，短超时）
        fd_set read_fds;
        FD_ZERO(&read_fds);
        FD_SET(sock, &read_fds);
        
        struct timeval timeout;
        timeout.tv_sec = 0;
        timeout.tv_usec = 100000;  // 100ms
        
        int result = select(sock + 1, &read_fds, NULL, NULL, &timeout);
        if (result <= 0 || !FD_ISSET(sock, &read_fds)) {
            continue;
        }
        
        // 接收数据包
        socklen_t from_len = sizeof(from_addr);
        ssize_t bytes_received = recvfrom(sock, buffer, sizeof(buffer), 0,
                                          (struct sockaddr *)&from_addr, &from_len);
        if (bytes_received < 0) {
            if (errno != EAGAIN && errno != EWOULDBLOCK) {
            }
            continue;
        }
        
        if (bytes_received < (ssize_t)sizeof(struct mtr_icmphdr)) {
            continue;
        }
        
        uint64_t recv_time = get_current_timestamp_ms();
        
        // 提取源 IP 地址
        char temp_src_ip[INET6_ADDRSTRLEN] = {0};
        if (from_addr.ss_family == AF_INET6) {
            struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)&from_addr;
            inet_ntop(AF_INET6, &addr6->sin6_addr, temp_src_ip, INET6_ADDRSTRLEN);
        } else if (from_addr.ss_family == AF_INET) {
            struct sockaddr_in *addr4 = (struct sockaddr_in *)&from_addr;
            inet_ntop(AF_INET, &addr4->sin_addr, temp_src_ip, INET6_ADDRSTRLEN);
        } else {
            continue;
        }
        
        // 解析 ICMP 响应
        int original_ttl = 0;
        int original_seq = 0;
        int is_echo_reply = 0;
        uint16_t icmp_id_value = 0;
        
        if (parse_icmp_response(buffer, (size_t)bytes_received, is_ipv6,
                               &original_ttl, &original_seq, &is_echo_reply, &icmp_id_value) != 0) {
            continue;
        }
        
        // session token 校验：不依赖 ICMP ID（可能被内核改写）
        // 只有能用 token 解码出合法 (ttl, probe_index) 的报文才认为属于本次 run
        if (original_seq <= 0) {
            continue;
        }
        uint16_t decoded = (uint16_t)(((uint16_t)original_seq) ^ seq_xor_token);
        int decoded_ttl = (int)((decoded >> 8) & 0xFF);
        int decoded_probe = (int)(decoded & 0xFF);
        if (decoded_ttl < 1 || decoded_ttl > max_ttl) {
            continue;
        }
        if (decoded_probe < 0 || decoded_probe >= times) {
            continue;
        }
        
        // 创建事件并推送到队列
        mtr_icmp_event event;
        memset(&event, 0, sizeof(event));
        event.probe_index = decoded_probe;
        event.recv_time = recv_time;
        event.is_echo_reply = is_echo_reply;
        safe_strncpy(event.src_ip, temp_src_ip, sizeof(event.src_ip));
        event.ttl = decoded_ttl;
        
        // 只有在 IP 不为空时才推送事件
        if (temp_src_ip[0] != '\0') {
            event_queue_push(queue, &event);
        }
    }
    
    return NULL;
}

// UDP 并行 worker 线程上下文
typedef struct {
    pthread_t thread;
    pthread_mutex_t mutex;
    int running;
    int stop;
    socket_t udp_sock;
    socket_t icmp_sock;                    // 用于接收 ICMP 错误消息
    mtr_udp_event_queue *event_queue;
    int is_ipv6;
    uint16_t dst_port_base;                // UDP 探测目的端口基址：dst_port = base + (ttl<<8) + probe_index
} udp_parallel_worker_ctx;

// UDP 并行 worker 线程：持续收包并推送到事件队列
static void *udp_parallel_worker_thread(void *arg) {
    udp_parallel_worker_ctx *ctx = (udp_parallel_worker_ctx *)arg;
    
    char buffer[MTR_RECV_BUFFER_SIZE];
    struct sockaddr_storage from_addr;
    fd_set read_fds, except_fds;
    
    while (1) {
        pthread_mutex_lock(&ctx->mutex);
        if (ctx->stop) {
            pthread_mutex_unlock(&ctx->mutex);
            break;
        }
        socket_t udp_sock = ctx->udp_sock;
        socket_t icmp_sock = ctx->icmp_sock;
        mtr_udp_event_queue *queue = ctx->event_queue;
        int is_ipv6 = ctx->is_ipv6;
        uint16_t dst_port_base = ctx->dst_port_base;
        pthread_mutex_unlock(&ctx->mutex);
        
        if (udp_sock < 0 || !queue) {
            usleep(10000);
            continue;
        }
        
        // 同时监听 UDP socket 和 ICMP socket（用于接收 ICMP 错误消息）
        FD_ZERO(&read_fds);
        FD_ZERO(&except_fds);
        FD_SET(udp_sock, &read_fds);
        FD_SET(udp_sock, &except_fds);
        int max_fd = udp_sock;
        
        if (icmp_sock >= 0) {
            FD_SET(icmp_sock, &read_fds);
            if (icmp_sock > max_fd) max_fd = icmp_sock;
        }
        
        struct timeval timeout;
        timeout.tv_sec = 0;
        timeout.tv_usec = 100000;  // 100ms
        
        int result = select(max_fd + 1, &read_fds, NULL, &except_fds, &timeout);
        if (result <= 0) {
            continue;
        }
        
        uint64_t recv_time = get_current_timestamp_ms();
        char temp_src_ip[INET6_ADDRSTRLEN] = {0};
        int ttl = 0;
        int probe_index = -1;
        int is_target_reply = 0;
        
        // 优先检查 ICMP socket（ICMP 错误消息）
        if (icmp_sock >= 0 && FD_ISSET(icmp_sock, &read_fds)) {
            socklen_t from_len = sizeof(from_addr);
            ssize_t bytes_received = recvfrom(icmp_sock, buffer, sizeof(buffer), 0,
                                              (struct sockaddr *)&from_addr, &from_len);
            if (bytes_received > 0) {
                // 提取源 IP
                if (from_addr.ss_family == AF_INET6) {
                    struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)&from_addr;
                    inet_ntop(AF_INET6, &addr6->sin6_addr, temp_src_ip, INET6_ADDRSTRLEN);
                } else if (from_addr.ss_family == AF_INET) {
                    struct sockaddr_in *addr4 = (struct sockaddr_in *)&from_addr;
                    inet_ntop(AF_INET, &addr4->sin_addr, temp_src_ip, INET6_ADDRSTRLEN);
                }
                
                // 解析 ICMP 响应以提取 TTL 和 probe_index
                int original_ttl = 0;
                int original_seq = 0;
                int is_echo_reply = 0;
                uint16_t icmp_id_value = 0;
                
                // 先检查 ICMP code 是否为 Port Unreachable（目标到达标志）
                // IPv4: ICMP_DEST_UNREACH (type=3), Port Unreachable (code=3)
                // IPv6: ICMP6_DST_UNREACH (type=1), Port Unreachable (code=4)
                uint8_t dest_unreach_type = is_ipv6 ? 1 : 3;
                uint8_t port_unreachable_code = is_ipv6 ? 4 : 3;
                
                // 跳过 IP 头（如果存在）
                const char *icmp_base = buffer;
                size_t icmp_len = bytes_received;
                uint8_t first_byte = (uint8_t)buffer[0];
                uint8_t ip_version = (first_byte >> 4) & 0x0F;
                
                if (ip_version == 4 && bytes_received >= 20) {
                    const struct ip *ip_hdr = (const struct ip *)buffer;
                    size_t ip_hdr_len = ip_hdr->ip_hl * 4;
                    if (ip_hdr_len >= 20 && ip_hdr_len <= bytes_received && bytes_received >= ip_hdr_len + 8) {
                        icmp_base = buffer + ip_hdr_len;
                        icmp_len = bytes_received - ip_hdr_len;
                    }
                } else if (ip_version == 6 && bytes_received >= 40) {
                    icmp_base = buffer + 40;
                    icmp_len = bytes_received - 40;
                }
                
                // 检查是否是 Port Unreachable
                if (icmp_len >= 2) {
                    uint8_t icmp_type = (uint8_t)icmp_base[0];
                    uint8_t icmp_code = (uint8_t)icmp_base[1];
                    if (icmp_type == dest_unreach_type && icmp_code == port_unreachable_code) {
                        is_target_reply = 1;  // Port Unreachable 表示到达目标
                    } else if (icmp_type == dest_unreach_type) {
                        // 收到 Destination Unreachable，但 code 不是 Port Unreachable
                    }
                }
                
                // 优先使用“内嵌 UDP 端口解码”的方式精确匹配 (ttl, probe_index)
                {
                    uint8_t icmp_type2 = 0;
                    uint8_t icmp_code2 = 0;
                    uint16_t orig_sp = 0;
                    uint16_t orig_dp = 0;
                    if (parse_icmp_embedded_udp_ports(buffer, (size_t)bytes_received, is_ipv6,
                                                      &icmp_type2, &icmp_code2, &orig_sp, &orig_dp) == 0) {
                        int dt = 0;
                        int dp = -1;
                        if (udp_probe_decode_from_dst_port(orig_dp, dst_port_base, &dt, &dp) == 0) {
                            ttl = dt;
                            probe_index = dp;
                        }
                    }
                }
                // 兜底：兼容旧逻辑（TTL-only）或异常报文
                if (ttl <= 0) {
                    int parse_ret = parse_icmp_response(buffer, (size_t)bytes_received, is_ipv6,
                                                        &original_ttl, &original_seq, &is_echo_reply, &icmp_id_value);
                    if (parse_ret == 0) {
                        ttl = original_ttl;
                        if (ttl == 0) ttl = 1;
                        probe_index = -1;
                    }
                }
            }
        }
        
        // 检查 UDP socket（只接收 ICMP 错误消息，不接收正常的 UDP 响应）
        // 注意：MTR 使用 UDP 时，目标端口通常是关闭的，不会收到正常的 UDP 响应
        // 只会收到 ICMP Time Exceeded 或 ICMP Destination Unreachable 消息
        if (FD_ISSET(udp_sock, &read_fds) || FD_ISSET(udp_sock, &except_fds)) {
            socklen_t from_len = sizeof(from_addr);
            ssize_t bytes_received = recvfrom(udp_sock, buffer, sizeof(buffer), MSG_DONTWAIT,
                                              (struct sockaddr *)&from_addr, &from_len);
            if (bytes_received > 0) {
                // 提取源 IP
                if (from_addr.ss_family == AF_INET6) {
                    struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)&from_addr;
                    inet_ntop(AF_INET6, &addr6->sin6_addr, temp_src_ip, INET6_ADDRSTRLEN);
                } else if (from_addr.ss_family == AF_INET) {
                    struct sockaddr_in *addr4 = (struct sockaddr_in *)&from_addr;
                    inet_ntop(AF_INET, &addr4->sin_addr, temp_src_ip, INET6_ADDRSTRLEN);
                }
                
                // 尝试解析 ICMP 错误消息（如果包含）
                int original_ttl = 0;
                int original_seq = 0;
                int is_echo_reply = 0;
                uint16_t icmp_id_value = 0;
                
                // 先检查是否是 ICMP 错误消息
                uint8_t dest_unreach_type = is_ipv6 ? 1 : 3;
                uint8_t port_unreachable_code = is_ipv6 ? 4 : 3;
                
                // 跳过 IP 头（如果存在）
                const char *icmp_base = buffer;
                size_t icmp_len = bytes_received;
                uint8_t first_byte = (uint8_t)buffer[0];
                uint8_t ip_version = (first_byte >> 4) & 0x0F;
                
                if (ip_version == 4 && bytes_received >= 20) {
                    const struct ip *ip_hdr = (const struct ip *)buffer;
                    size_t ip_hdr_len = ip_hdr->ip_hl * 4;
                    if (ip_hdr_len >= 20 && ip_hdr_len <= bytes_received && bytes_received >= ip_hdr_len + 8) {
                        icmp_base = buffer + ip_hdr_len;
                        icmp_len = bytes_received - ip_hdr_len;
                    }
                } else if (ip_version == 6 && bytes_received >= 40) {
                    icmp_base = buffer + 40;
                    icmp_len = bytes_received - 40;
                }
                
                // 检查是否是 Port Unreachable
                int is_icmp_error = 0;
                if (icmp_len >= 2) {
                    uint8_t icmp_type = (uint8_t)icmp_base[0];
                    uint8_t icmp_code = (uint8_t)icmp_base[1];
                    // 记录所有收到的 ICMP 消息类型，用于调试
                    if (icmp_type == dest_unreach_type) {
                        is_icmp_error = 1;
                        if (icmp_code == port_unreachable_code) {
                            is_target_reply = 1;  // Port Unreachable 表示到达目标
                        } else {
                            is_target_reply = 0;  // 其他 Destination Unreachable 不是目标回复
                        }
                    }
                }
                
                // 优先使用“内嵌 UDP 端口解码”的方式精确匹配 (ttl, probe_index)
                {
                    uint8_t icmp_type2 = 0;
                    uint8_t icmp_code2 = 0;
                    uint16_t orig_sp = 0;
                    uint16_t orig_dp = 0;
                    if (parse_icmp_embedded_udp_ports(buffer, (size_t)bytes_received, is_ipv6,
                                                      &icmp_type2, &icmp_code2, &orig_sp, &orig_dp) == 0) {
                        int dt = 0;
                        int dp = -1;
                        if (udp_probe_decode_from_dst_port(orig_dp, dst_port_base, &dt, &dp) == 0) {
                            ttl = dt;
                            probe_index = dp;
                        }
                    }
                }
                // 兜底：兼容旧逻辑（TTL-only）或异常报文
                if (ttl <= 0) {
                    int parse_ret = parse_icmp_response(buffer, (size_t)bytes_received, is_ipv6,
                                                        &original_ttl, &original_seq, &is_echo_reply, &icmp_id_value);
                    if (parse_ret == 0) {
                        ttl = original_ttl;
                        if (ttl == 0) ttl = 1;
                        probe_index = -1;
                    }
                }
            }
        }
        
        // 如果成功解析到事件，推送到队列
        if (ttl > 0 && temp_src_ip[0] != '\0') {
            mtr_udp_event event;
            memset(&event, 0, sizeof(event));
            event.ttl = ttl;
            event.probe_index = probe_index;
            event.recv_time = recv_time;
            event.is_target_reply = is_target_reply;
            safe_strncpy(event.src_ip, temp_src_ip, sizeof(event.src_ip));  
            udp_event_queue_push(queue, &event);
        }
    }
    
    return NULL;
}

// UDP 并行 worker 启动和停止函数
static int udp_parallel_worker_start(udp_parallel_worker_ctx *ctx, socket_t udp_sock, socket_t icmp_sock,
                                     mtr_udp_event_queue *queue, int is_ipv6, uint16_t dst_port_base) {
    if (!ctx || udp_sock < 0 || !queue) return -1;
    
    pthread_mutex_lock(&ctx->mutex);
    if (ctx->running) {
        pthread_mutex_unlock(&ctx->mutex);
        return 0;
    }
    
    ctx->udp_sock = udp_sock;
    ctx->icmp_sock = icmp_sock;
    ctx->event_queue = queue;
    ctx->is_ipv6 = is_ipv6;
    ctx->dst_port_base = dst_port_base;
    ctx->stop = 0;
    
    int ret = pthread_create(&ctx->thread, NULL, udp_parallel_worker_thread, ctx);
    if (ret != 0) {
        ctx->udp_sock = -1;
        pthread_mutex_unlock(&ctx->mutex);
        return -1;
    }
    
    ctx->running = 1;
    pthread_mutex_unlock(&ctx->mutex);
    return 0;
}

static void udp_parallel_worker_stop(udp_parallel_worker_ctx *ctx) {
    if (!ctx) return;
    
    pthread_mutex_lock(&ctx->mutex);
    if (!ctx->running) {
        pthread_mutex_unlock(&ctx->mutex);
        return;
    }
    
    ctx->stop = 1;
    pthread_mutex_unlock(&ctx->mutex);
    
    pthread_join(ctx->thread, NULL);
    
    pthread_mutex_lock(&ctx->mutex);
    ctx->running = 0;
    ctx->udp_sock = -1;
    ctx->icmp_sock = -1;
    pthread_mutex_unlock(&ctx->mutex);
}

// TCP 并行 worker 线程上下文
typedef struct {
    pthread_t thread;
    pthread_mutex_t mutex;
    int running;
    int stop;
    socket_t *tcp_sockets;                // TCP socket 数组
    int tcp_socket_count;                 // socket 数量
    socket_t icmp_sock;                   // ICMP socket 用于接收 ICMP 错误消息
    mtr_tcp_event_queue *event_queue;
    int is_ipv6;
    char target_ip[INET6_ADDRSTRLEN];    // 目标IP，用于识别连接被拒绝时的源IP
    uint16_t src_port_base;              // TCP 探测源端口基址：src_port = base + (ttl<<8) + probe_index
} tcp_parallel_worker_ctx;

// TCP 探测：源端口编码/解码（用于 ICMP payload 匹配）
// 编码：src_port = base + (ttl<<8) + (probe_index & 0xFF)
static int tcp_probe_decode_from_src_port(uint16_t src_port, uint16_t base, int *ttl_out, int *probe_index_out) {
    if (!ttl_out || !probe_index_out) return -1;
    if (src_port < base) return -1;
    uint32_t delta = (uint32_t)(src_port - base);
    int ttl = (int)((delta >> 8) & 0xFF);
    int probe_index = (int)(delta & 0xFF);
    if (ttl < 1 || ttl > 255) return -1;
    *ttl_out = ttl;
    *probe_index_out = probe_index;
    return 0;
}

// IPv6：在“内层 IPv6 报文”中定位传输层头（跳过扩展头）
// 仅用于解析 ICMP payload 内嵌的原始报文（TCP/UDP）。
static int mtr_ipv6_locate_transport_header(const uint8_t *ipv6_pkt,
                                            size_t ipv6_len,
                                            uint8_t *proto_out,
                                            const uint8_t **l4_out,
                                            size_t *l4_len_out) {
    if (!ipv6_pkt || ipv6_len < 40 || !proto_out || !l4_out || !l4_len_out) return -1;
    uint8_t next = ipv6_pkt[6];
    size_t off = 40;

    // 处理常见扩展头：
    // - Hop-by-Hop (0), Routing (43), Destination Options (60): len=(hdrlen+1)*8
    // - Fragment (44): 固定 8 字节
    // - AH (51): len=(hdrlen+2)*4
    // - ESP (50): 无法可靠跳过（加密），直接失败
    // - No Next Header (59): 失败
    while (1) {
        switch (next) {
            case 0:   // Hop-by-Hop
            case 43:  // Routing
            case 60: { // Destination Options
                if (ipv6_len < off + 2) return -1;
                uint8_t hdr_next = ipv6_pkt[off + 0];
                uint8_t hdr_len8 = ipv6_pkt[off + 1];
                size_t ext_len = (size_t)(hdr_len8 + 1) * 8;
                if (ipv6_len < off + ext_len) return -1;
                next = hdr_next;
                off += ext_len;
                continue;
            }
            case 44: { // Fragment
                if (ipv6_len < off + 8) return -1;
                uint8_t hdr_next = ipv6_pkt[off + 0];
                next = hdr_next;
                off += 8;
                continue;
            }
            case 51: { // AH
                if (ipv6_len < off + 2) return -1;
                uint8_t hdr_next = ipv6_pkt[off + 0];
                uint8_t hdr_len4 = ipv6_pkt[off + 1];
                size_t ext_len = (size_t)(hdr_len4 + 2) * 4;
                if (ipv6_len < off + ext_len) return -1;
                next = hdr_next;
                off += ext_len;
                continue;
            }
            case 50: // ESP（无法解析长度）
            case 59: // No Next Header
                return -1;
            default:
                *proto_out = next;
                *l4_out = ipv6_pkt + off;
                *l4_len_out = (ipv6_len > off) ? (ipv6_len - off) : 0;
                return 0;
        }
    }
}

// UDP 探测：目的端口编码/解码（用于 ICMP payload 匹配）
// 编码：dst_port = base + (ttl<<8) + (probe_index & 0xFF)
static int udp_probe_decode_from_dst_port(uint16_t dst_port, uint16_t base, int *ttl_out, int *probe_index_out) {
    if (!ttl_out || !probe_index_out) return -1;
    if (dst_port < base) return -1;
    uint32_t delta = (uint32_t)(dst_port - base);
    int ttl = (int)((delta >> 8) & 0xFF);
    int probe_index = (int)(delta & 0xFF);
    if (ttl < 1 || ttl > 255) return -1;
    *ttl_out = ttl;
    *probe_index_out = probe_index;
    return 0;
}

// 从 ICMP 错误报文中解析“原始 TCP 头”的源/目的端口
// 仅用于 TCP MTR：通过端口解码出 (ttl, probe_index)，从而精确匹配
static int parse_icmp_embedded_tcp_ports(const char *buffer, size_t buffer_len, int is_ipv6,
                                        uint8_t *icmp_type_out, uint8_t *icmp_code_out,
                                        uint16_t *orig_src_port_out, uint16_t *orig_dst_port_out) {
    if (!buffer || buffer_len < 8 || !orig_src_port_out || !orig_dst_port_out) return -1;

    // 跳过可能存在的外层 IP 头，只解析 ICMP
    const char *icmp_base = buffer;
    size_t icmp_len = buffer_len;
    uint8_t first_byte = (uint8_t)buffer[0];
    uint8_t ip_version = (first_byte >> 4) & 0x0F;

    if (ip_version == 4 && buffer_len >= sizeof(struct ip)) {
        const struct ip *ip_hdr = (const struct ip *)buffer;
        size_t ip_hdr_len = ip_hdr->ip_hl * 4;
        if (ip_hdr_len >= 20 && ip_hdr_len <= buffer_len && buffer_len >= ip_hdr_len + 8) {
            icmp_base = buffer + ip_hdr_len;
            icmp_len = buffer_len - ip_hdr_len;
        }
    } else if (ip_version == 6 && buffer_len >= 40) {
        icmp_base = buffer + 40;
        icmp_len = buffer_len - 40;
    }

    if (icmp_len < 8) return -1;
    uint8_t icmp_type = (uint8_t)icmp_base[0];
    uint8_t icmp_code = (uint8_t)icmp_base[1];
    if (icmp_type_out) *icmp_type_out = icmp_type;
    if (icmp_code_out) *icmp_code_out = icmp_code;

    // Echo Reply 不属于 TCP 探测响应
    if ((!is_ipv6 && icmp_type == 0) || (is_ipv6 && icmp_type == 129)) return -1;

    // ICMP 错误报文：后面会携带“原始 IP 头 + 原始传输层头”
    const char *inner = icmp_base + 8;
    size_t inner_len = icmp_len - 8;
    if (inner_len < 20) return -1;

    uint8_t inner_first = (uint8_t)inner[0];
    uint8_t inner_ver = (inner_first >> 4) & 0x0F;

    const char *l4 = NULL;
    size_t l4_len = 0;
    uint8_t proto = 0;

    if (inner_ver == 4) {
        if (inner_len < (size_t)sizeof(struct ip)) return -1;
        const struct ip *inner_ip = (const struct ip *)inner;
        size_t ihl = inner_ip->ip_hl * 4;
        if (ihl < 20 || ihl > inner_len) return -1;
        proto = inner_ip->ip_p;
        l4 = inner + ihl;
        l4_len = inner_len - ihl;
    } else if (inner_ver == 6) {
        if (inner_len < 40) return -1;
        const uint8_t *l4p = NULL;
        size_t l4plen = 0;
        if (mtr_ipv6_locate_transport_header((const uint8_t *)inner, inner_len, &proto, &l4p, &l4plen) != 0) return -1;
        l4 = (const char *)l4p;
        l4_len = l4plen;
    } else {
        return -1;
    }

    if (proto != IPPROTO_TCP) return -1;
    if (l4_len < 4) return -1;

    const uint16_t *sp = (const uint16_t *)(const void *)(l4 + 0);
    const uint16_t *dp = (const uint16_t *)(const void *)(l4 + 2);
    *orig_src_port_out = ntohs(*sp);
    *orig_dst_port_out = ntohs(*dp);
    return 0;
}

// 从 ICMP 错误报文中解析“原始 UDP 头”的源/目的端口
// 用于 UDP MTR：通过 dst_port 解码出 (ttl, probe_index)，实现精确匹配
static int parse_icmp_embedded_udp_ports(const char *buffer, size_t buffer_len, int is_ipv6,
                                        uint8_t *icmp_type_out, uint8_t *icmp_code_out,
                                        uint16_t *orig_src_port_out, uint16_t *orig_dst_port_out) {
    if (!buffer || buffer_len < 8 || !orig_src_port_out || !orig_dst_port_out) return -1;

    // 跳过可能存在的外层 IP 头，只解析 ICMP
    const char *icmp_base = buffer;
    size_t icmp_len = buffer_len;
    uint8_t first_byte = (uint8_t)buffer[0];
    uint8_t ip_version = (first_byte >> 4) & 0x0F;

    if (ip_version == 4 && buffer_len >= sizeof(struct ip)) {
        const struct ip *ip_hdr = (const struct ip *)buffer;
        size_t ip_hdr_len = ip_hdr->ip_hl * 4;
        if (ip_hdr_len >= 20 && ip_hdr_len <= buffer_len && buffer_len >= ip_hdr_len + 8) {
            icmp_base = buffer + ip_hdr_len;
            icmp_len = buffer_len - ip_hdr_len;
        }
    } else if (ip_version == 6 && buffer_len >= 40) {
        icmp_base = buffer + 40;
        icmp_len = buffer_len - 40;
    }

    if (icmp_len < 8) return -1;
    uint8_t icmp_type = (uint8_t)icmp_base[0];
    uint8_t icmp_code = (uint8_t)icmp_base[1];
    if (icmp_type_out) *icmp_type_out = icmp_type;
    if (icmp_code_out) *icmp_code_out = icmp_code;

    // ICMP 错误报文：后面会携带“原始 IP 头 + 原始传输层头”
    const char *inner = icmp_base + 8;
    size_t inner_len = icmp_len - 8;
    if (inner_len < 20) return -1;

    uint8_t inner_first = (uint8_t)inner[0];
    uint8_t inner_ver = (inner_first >> 4) & 0x0F;

    const char *l4 = NULL;
    size_t l4_len = 0;
    uint8_t proto = 0;

    if (inner_ver == 4) {
        if (inner_len < (size_t)sizeof(struct ip)) return -1;
        const struct ip *inner_ip = (const struct ip *)inner;
        size_t ihl = inner_ip->ip_hl * 4;
        if (ihl < 20 || ihl > inner_len) return -1;
        proto = inner_ip->ip_p;
        l4 = inner + ihl;
        l4_len = inner_len - ihl;
    } else if (inner_ver == 6) {
        if (inner_len < 40) return -1;
        const uint8_t *l4p = NULL;
        size_t l4plen = 0;
        if (mtr_ipv6_locate_transport_header((const uint8_t *)inner, inner_len, &proto, &l4p, &l4plen) != 0) return -1;
        l4 = (const char *)l4p;
        l4_len = l4plen;
    } else {
        return -1;
    }

    if (proto != IPPROTO_UDP) return -1;
    if (l4_len < 4) return -1;

    const uint16_t *sp = (const uint16_t *)(const void *)(l4 + 0);
    const uint16_t *dp = (const uint16_t *)(const void *)(l4 + 2);
    *orig_src_port_out = ntohs(*sp);
    *orig_dst_port_out = ntohs(*dp);
    return 0;
}

// 创建 TCP probe socket，并绑定指定源端口（用于编码 TTL/probe_index）
static socket_t create_tcp_probe_socket(int is_ipv6, unsigned int interface_index, uint16_t bind_port) {
    int domain = is_ipv6 ? AF_INET6 : AF_INET;
    socket_t sock = socket(domain, SOCK_STREAM, IPPROTO_TCP);
    if (sock < 0) return -1;

    int reuse = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    // 绑定到指定网络接口（IPv4 使用 IP_BOUND_IF；IPv6 尝试 IPV6_BOUND_IF）
    if (interface_index > 0) {
        if (!is_ipv6) {
            setsockopt(sock, IPPROTO_IP, IP_BOUND_IF, &interface_index, sizeof(interface_index));
        } else {
#ifdef IPV6_BOUND_IF
            setsockopt(sock, IPPROTO_IPV6, IPV6_BOUND_IF, &interface_index, sizeof(interface_index));
#endif
        }
    }

    // 绑定源端口
    if (is_ipv6) {
        struct sockaddr_in6 local6;
        memset(&local6, 0, sizeof(local6));
        local6.sin6_family = AF_INET6;
        local6.sin6_port = htons(bind_port);
        local6.sin6_addr = in6addr_any;
        if (bind(sock, (struct sockaddr *)&local6, sizeof(local6)) < 0) {
            close(sock);
            return -1;
        }
    } else {
        struct sockaddr_in local4;
        memset(&local4, 0, sizeof(local4));
        local4.sin_family = AF_INET;
        local4.sin_port = htons(bind_port);
        local4.sin_addr.s_addr = htonl(INADDR_ANY);
        if (bind(sock, (struct sockaddr *)&local4, sizeof(local4)) < 0) {
            close(sock);
            return -1;
        }
    }

    return sock;
}

// TCP 并行 worker 线程：持续收包并推送到事件队列
static void *tcp_parallel_worker_thread(void *arg) {
    tcp_parallel_worker_ctx *ctx = (tcp_parallel_worker_ctx *)arg;
    
    char buffer[MTR_RECV_BUFFER_SIZE];
    struct sockaddr_storage from_addr;
    fd_set read_fds, write_fds, except_fds;
    
    while (1) {
        pthread_mutex_lock(&ctx->mutex);
        if (ctx->stop) {
            pthread_mutex_unlock(&ctx->mutex);
            break;
        }
        socket_t *tcp_sockets = ctx->tcp_sockets;
        int tcp_socket_count = ctx->tcp_socket_count;
        socket_t icmp_sock = ctx->icmp_sock;
        mtr_tcp_event_queue *queue = ctx->event_queue;
        int is_ipv6 = ctx->is_ipv6;
        char target_ip[INET6_ADDRSTRLEN];
        safe_strncpy(target_ip, ctx->target_ip, sizeof(target_ip));
        uint16_t port_base = ctx->src_port_base;
        pthread_mutex_unlock(&ctx->mutex);
        
        if (!tcp_sockets || tcp_socket_count <= 0 || !queue) {
            usleep(10000);
            continue;
        }
        
        // 同时监听所有 TCP sockets 和 ICMP socket（用于接收 ICMP 错误消息）
        FD_ZERO(&read_fds);
        FD_ZERO(&write_fds);
        FD_ZERO(&except_fds);
        int max_fd = -1;
        
        // 添加所有 TCP sockets
        pthread_mutex_lock(&ctx->mutex);
        for (int i = 0; i < tcp_socket_count; i++) {
            if (tcp_sockets[i] >= 0) {
                FD_SET(tcp_sockets[i], &read_fds);
                // 非阻塞 connect() 的完成通常体现在“可写”
                FD_SET(tcp_sockets[i], &write_fds);
                FD_SET(tcp_sockets[i], &except_fds);
                if (tcp_sockets[i] > max_fd) max_fd = tcp_sockets[i];
            }
        }
        pthread_mutex_unlock(&ctx->mutex);
        
        // 添加 ICMP socket
        if (icmp_sock >= 0) {
            FD_SET(icmp_sock, &read_fds);
            if (icmp_sock > max_fd) max_fd = icmp_sock;
        }
        
        if (max_fd < 0) {
            usleep(10000);
            continue;
        }
        
        struct timeval timeout;
        timeout.tv_sec = 0;
        timeout.tv_usec = 100000;  // 100ms
        
        int result = select(max_fd + 1, &read_fds, &write_fds, &except_fds, &timeout);
        if (result <= 0) {
            continue;
        }
        
        uint64_t recv_time = get_current_timestamp_ms();
        char temp_src_ip[INET6_ADDRSTRLEN] = {0};
        int ttl = 0;
        int probe_index = -1;
        int is_target_reply = 0;
        
        // 优先检查 ICMP socket（ICMP 错误消息：Time Exceeded、Destination Unreachable 等）
        if (icmp_sock >= 0 && FD_ISSET(icmp_sock, &read_fds)) {
            socklen_t from_len = sizeof(from_addr);
            ssize_t bytes_received = recvfrom(icmp_sock, buffer, sizeof(buffer), 0,
                                              (struct sockaddr *)&from_addr, &from_len);
            if (bytes_received > 0) {
                // 提取源 IP
                if (from_addr.ss_family == AF_INET6) {
                    struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)&from_addr;
                    inet_ntop(AF_INET6, &addr6->sin6_addr, temp_src_ip, INET6_ADDRSTRLEN);
                } else if (from_addr.ss_family == AF_INET) {
                    struct sockaddr_in *addr4 = (struct sockaddr_in *)&from_addr;
                    inet_ntop(AF_INET, &addr4->sin_addr, temp_src_ip, INET6_ADDRSTRLEN);
                }

                // 解析 ICMP payload 中的原始 TCP 端口，解码出 (ttl, probe_index)
                uint8_t icmp_type = 0;
                uint8_t icmp_code = 0;
                uint16_t orig_src_port = 0;
                uint16_t orig_dst_port = 0;
                int p_ret = parse_icmp_embedded_tcp_ports(buffer, (size_t)bytes_received, is_ipv6,
                                                          &icmp_type, &icmp_code, &orig_src_port, &orig_dst_port);
                if (p_ret == 0) {
                    int decoded_ttl = 0;
                    int decoded_probe = -1;
                    if (tcp_probe_decode_from_src_port(orig_src_port, port_base, &decoded_ttl, &decoded_probe) == 0) {
                        ttl = decoded_ttl;
                        probe_index = decoded_probe;
                        is_target_reply = 0; // ICMP 错误消息默认来自中间路由器

                        mtr_tcp_event event;
                        memset(&event, 0, sizeof(event));
                        event.ttl = ttl;
                        event.probe_index = probe_index;
                        event.recv_time = recv_time;
                        event.is_target_reply = is_target_reply;
                        safe_strncpy(event.src_ip, temp_src_ip, sizeof(event.src_ip));


                        tcp_event_queue_push(queue, &event);

                        // 找到对应的 probe socket 并关闭（释放并发槽位）
                        pthread_mutex_lock(&ctx->mutex);
                        for (int si = 0; si < tcp_socket_count; si++) {
                            socket_t ps = tcp_sockets[si];
                            if (ps < 0) continue;
                            uint16_t local_port = 0;
                            if (is_ipv6) {
                                struct sockaddr_in6 la6;
                                socklen_t llen = sizeof(la6);
                                if (getsockname(ps, (struct sockaddr *)&la6, &llen) == 0) {
                                    local_port = ntohs(la6.sin6_port);
                                }
                            } else {
                                struct sockaddr_in la4;
                                socklen_t llen = sizeof(la4);
                                if (getsockname(ps, (struct sockaddr *)&la4, &llen) == 0) {
                                    local_port = ntohs(la4.sin_port);
                                }
                            }
                            if (local_port == orig_src_port) {
                                close(ps);
                                tcp_sockets[si] = -1;
                                break;
                            }
                        }
                        pthread_mutex_unlock(&ctx->mutex);
                    }
                }
            }
        }
        
        // 检查 TCP sockets（接收 TCP SYN-ACK 或 RST，或检测连接状态变化）
        for (int i = 0; i < tcp_socket_count; i++) {
            pthread_mutex_lock(&ctx->mutex);
            socket_t sock = tcp_sockets[i];
            pthread_mutex_unlock(&ctx->mutex);
            if (sock < 0) continue;

            // connect 完成：通常表现为 write-ready 或 except
            if (FD_ISSET(sock, &write_fds) || FD_ISSET(sock, &except_fds)) {
                int so_error = 0;
                socklen_t error_len = sizeof(so_error);
                if (getsockopt(sock, SOL_SOCKET, SO_ERROR, &so_error, &error_len) == 0) {
                    if (so_error == 0 || so_error == ECONNREFUSED) {
                        // 通过本地端口解码 (ttl, probe_index)
                        uint16_t local_port = 0;
                        if (is_ipv6) {
                            struct sockaddr_in6 la6;
                            socklen_t llen = sizeof(la6);
                            if (getsockname(sock, (struct sockaddr *)&la6, &llen) == 0) {
                                local_port = ntohs(la6.sin6_port);
                            }
                        } else {
                            struct sockaddr_in la4;
                            socklen_t llen = sizeof(la4);
                            if (getsockname(sock, (struct sockaddr *)&la4, &llen) == 0) {
                                local_port = ntohs(la4.sin_port);
                            }
                        }

                        int decoded_ttl = 0;
                        int decoded_probe = -1;
                        if (local_port != 0 && tcp_probe_decode_from_src_port(local_port, port_base, &decoded_ttl, &decoded_probe) == 0) {
                            ttl = decoded_ttl;
                            probe_index = decoded_probe;
                            is_target_reply = 1; // TCP 连接成功/拒绝都表示“到达目标”

                            mtr_tcp_event event;
                            memset(&event, 0, sizeof(event));
                            event.ttl = ttl;
                            event.probe_index = probe_index;
                            event.recv_time = recv_time;
                            event.is_target_reply = is_target_reply;
                            safe_strncpy(event.src_ip, target_ip, sizeof(event.src_ip));
                            tcp_event_queue_push(queue, &event);

                            // 对已建立连接，使用 abortive close（RST）快速释放
                            if (so_error == 0) {
                                struct linger lg;
                                lg.l_onoff = 1;
                                lg.l_linger = 0;
                                setsockopt(sock, SOL_SOCKET, SO_LINGER, &lg, sizeof(lg));
                            }

                            pthread_mutex_lock(&ctx->mutex);
                            // 再次确认当前 slot 仍是该 fd 后关闭
                            if (tcp_sockets[i] == sock) {
                                close(sock);
                                tcp_sockets[i] = -1;
                            }
                            pthread_mutex_unlock(&ctx->mutex);
                        }
                    }
                }
            }
        }
    }
    
    return NULL;
}

// TCP 并行 worker 启动和停止函数
static int tcp_parallel_worker_start(tcp_parallel_worker_ctx *ctx, socket_t *tcp_sockets, int tcp_socket_count,
                                      socket_t icmp_sock, mtr_tcp_event_queue *queue, int is_ipv6, const char *target_ip,
                                      uint16_t src_port_base) {
    if (!ctx || !tcp_sockets || tcp_socket_count <= 0 || !queue || !target_ip) return -1;
    
    pthread_mutex_lock(&ctx->mutex);
    if (ctx->running) {
        pthread_mutex_unlock(&ctx->mutex);
        return 0;
    }
    
    ctx->tcp_sockets = tcp_sockets;
    ctx->tcp_socket_count = tcp_socket_count;
    ctx->icmp_sock = icmp_sock;
    ctx->event_queue = queue;
    ctx->is_ipv6 = is_ipv6;
    safe_strncpy(ctx->target_ip, target_ip, sizeof(ctx->target_ip));
    ctx->src_port_base = src_port_base;
    ctx->stop = 0;
    
    int ret = pthread_create(&ctx->thread, NULL, tcp_parallel_worker_thread, ctx);
    if (ret != 0) {
        ctx->tcp_sockets = NULL;
        pthread_mutex_unlock(&ctx->mutex);
        return -1;
    }
    
    ctx->running = 1;
    pthread_mutex_unlock(&ctx->mutex);
    return 0;
}

static void tcp_parallel_worker_stop(tcp_parallel_worker_ctx *ctx) {
    if (!ctx) return;
    
    pthread_mutex_lock(&ctx->mutex);
    if (!ctx->running) {
        pthread_mutex_unlock(&ctx->mutex);
        return;
    }
    
    ctx->stop = 1;
    pthread_mutex_unlock(&ctx->mutex);
    
    pthread_join(ctx->thread, NULL);
    
    pthread_mutex_lock(&ctx->mutex);
    ctx->running = 0;
    ctx->tcp_sockets = NULL;
    ctx->tcp_socket_count = 0;
    ctx->icmp_sock = -1;
    pthread_mutex_unlock(&ctx->mutex);
}

// 发送 UDP 包（返回 0 成功；失败返回 -1，并通过 out_errno 输出 errno）
static int send_udp_packet(socket_t udp_socket, const char *target_ip, int ttl,
                           int sequence, uint16_t dst_port_base, uint16_t *src_port, uint64_t *send_time,
                           int *out_errno, const char **out_failed_op) {
    if (!target_ip || udp_socket < 0 || ttl < 1 || ttl > 255) return -1;
    if (out_errno) *out_errno = 0;
    if (out_failed_op) *out_failed_op = NULL;
    
    int is_ipv6 = (strchr(target_ip, ':') != NULL);
    
    // 设置 TTL
    int ttl_value = ttl;
    if (is_ipv6) {
        if (setsockopt(udp_socket, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &ttl_value, sizeof(ttl_value)) < 0) {
            if (out_errno) *out_errno = errno;
            if (out_failed_op) *out_failed_op = "setsockopt";
            return -1;
        }
    } else {
        if (setsockopt(udp_socket, IPPROTO_IP, IP_TTL, &ttl_value, sizeof(ttl_value)) < 0) {
            if (out_errno) *out_errno = errno;
            if (out_failed_op) *out_failed_op = "setsockopt";
            return -1;
        }
    }
    
    // 获取源端口
    if (src_port) {
        if (is_ipv6) {
            struct sockaddr_in6 bound_addr;
            socklen_t addr_len = sizeof(bound_addr);
            if (getsockname(udp_socket, (struct sockaddr *)&bound_addr, &addr_len) == 0) {
                *src_port = ntohs(bound_addr.sin6_port);
            } else {
                *src_port = 0;
            }
        } else {
            struct sockaddr_in bound_addr;
            socklen_t addr_len = sizeof(bound_addr);
            if (getsockname(udp_socket, (struct sockaddr *)&bound_addr, &addr_len) == 0) {
                *src_port = ntohs(bound_addr.sin_port);
            } else {
                *src_port = 0;
            }
        }
    }
    
    // 构建目标地址
    char data[32];
    memset(data, 0, sizeof(data));
    snprintf(data, sizeof(data), "MTR-%d-%d", ttl, sequence);
    
    // UDP：目的端口编码 ttl/probe_index，用于从 ICMP payload 精确解码
    uint16_t encoded_delta = (uint16_t)(((ttl & 0xFF) << 8) | (sequence & 0xFF));
    uint16_t dst_port = (uint16_t)(dst_port_base + encoded_delta);
    
    ssize_t sent = 0;
    if (is_ipv6) {
        struct sockaddr_in6 addr6;
        memset(&addr6, 0, sizeof(addr6));
        addr6.sin6_family = AF_INET6;
        if (inet_pton(AF_INET6, target_ip, &addr6.sin6_addr) != 1) {
            if (out_errno) *out_errno = EINVAL;
            if (out_failed_op) *out_failed_op = "inet_pton";
            return -1;
        }
        addr6.sin6_port = htons(dst_port);
        sent = sendto(udp_socket, data, sizeof(data), 0, (struct sockaddr *)&addr6, sizeof(addr6));
    } else {
        struct sockaddr_in addr4;
        memset(&addr4, 0, sizeof(addr4));
        addr4.sin_family = AF_INET;
        if (inet_pton(AF_INET, target_ip, &addr4.sin_addr) != 1) {
            if (out_errno) *out_errno = EINVAL;
            if (out_failed_op) *out_failed_op = "inet_pton";
            return -1;
        }
        addr4.sin_port = htons(dst_port);
        sent = sendto(udp_socket, data, sizeof(data), 0, (struct sockaddr *)&addr4, sizeof(addr4));
    }
    
    if (sent < 0 || sent != (ssize_t)sizeof(data)) {
        if (out_errno) *out_errno = errno;
        if (out_failed_op) *out_failed_op = "sendto";
        return -1;
    }
    
    if (send_time) {
        *send_time = get_current_timestamp_ms();
    }
    
    return 0;
}

// 发送 TCP SYN 包（返回 0 成功；失败返回 -1，并通过 out_errno 输出 errno）
static int send_tcp_syn(socket_t tcp_socket, const char *target_ip, int ttl,
                        int sequence, uint16_t *src_port, uint64_t *send_time,
                        int *out_errno, const char **out_failed_op) {
    if (!target_ip || tcp_socket < 0 || ttl < 1 || ttl > 255) return -1;
    if (out_errno) *out_errno = 0;
    if (out_failed_op) *out_failed_op = NULL;
    
    int is_ipv6 = (strchr(target_ip, ':') != NULL);
    
    // 设置 TTL
    int ttl_value = ttl;
    if (is_ipv6) {
        if (setsockopt(tcp_socket, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &ttl_value, sizeof(ttl_value)) < 0) {
            if (out_errno) *out_errno = errno;
            if (out_failed_op) *out_failed_op = "setsockopt";
            return -1;
        }
    } else {
        if (setsockopt(tcp_socket, IPPROTO_IP, IP_TTL, &ttl_value, sizeof(ttl_value)) < 0) {
            if (out_errno) *out_errno = errno;
            if (out_failed_op) *out_failed_op = "setsockopt";
            return -1;
        }
    }
    
    // 获取源端口
    if (src_port) {
        if (is_ipv6) {
            struct sockaddr_in6 bound_addr;
            socklen_t addr_len = sizeof(bound_addr);
            if (getsockname(tcp_socket, (struct sockaddr *)&bound_addr, &addr_len) == 0) {
                *src_port = ntohs(bound_addr.sin6_port);
            } else {
                *src_port = 0;
            }
        } else {
            struct sockaddr_in bound_addr;
            socklen_t addr_len = sizeof(bound_addr);
            if (getsockname(tcp_socket, (struct sockaddr *)&bound_addr, &addr_len) == 0) {
                *src_port = ntohs(bound_addr.sin_port);
            } else {
                *src_port = 0;
            }
        }
    }
    
    // 构建目标地址并连接（非阻塞）
    int flags = fcntl(tcp_socket, F_GETFL, 0);
    fcntl(tcp_socket, F_SETFL, flags | O_NONBLOCK);
    
    int connect_result = -1;
    if (is_ipv6) {
        struct sockaddr_in6 addr6;
        memset(&addr6, 0, sizeof(addr6));
        addr6.sin6_family = AF_INET6;
        if (inet_pton(AF_INET6, target_ip, &addr6.sin6_addr) != 1) {
            if (out_errno) *out_errno = EINVAL;
            if (out_failed_op) *out_failed_op = "inet_pton";
            fcntl(tcp_socket, F_SETFL, flags);
            return -1;
        }
        addr6.sin6_port = htons(MTR_TCP_DST_PORT);
        connect_result = connect(tcp_socket, (struct sockaddr *)&addr6, sizeof(addr6));
    } else {
        struct sockaddr_in addr4;
        memset(&addr4, 0, sizeof(addr4));
        addr4.sin_family = AF_INET;
        if (inet_pton(AF_INET, target_ip, &addr4.sin_addr) != 1) {
            if (out_errno) *out_errno = EINVAL;
            if (out_failed_op) *out_failed_op = "inet_pton";
            fcntl(tcp_socket, F_SETFL, flags);
            return -1;
        }
        addr4.sin_port = htons(MTR_TCP_DST_PORT);
        connect_result = connect(tcp_socket, (struct sockaddr *)&addr4, sizeof(addr4));
    }
    
    // 检查 connect() 返回值
    if (connect_result < 0) {
        if (errno == EINPROGRESS) {
            // 正常情况：非阻塞模式下，EINPROGRESS 表示连接正在进行中，SYN 包已发送
        } else if (errno == EALREADY) {
            // Socket 已经在连接中，等待完成或重置
            // 检查 socket 错误状态
            int so_error = 0;
            socklen_t len = sizeof(so_error);
            if (getsockopt(tcp_socket, SOL_SOCKET, SO_ERROR, &so_error, &len) == 0) {
            }
        } else if (errno == EISCONN) {
            // Socket 已经连接，说明之前的连接已成功建立
            // 对于MTR探测，这是正常的：连接建立表示到达目标（端口开放）
            // 不应该关闭连接，而是保持连接打开，让worker线程检测连接状态
            // 不关闭连接，保持连接打开，让worker线程通过getpeername()和SO_ERROR检测连接状态
            // 返回成功，表示探测已发送（虽然使用的是已存在的连接）
        } else {
            // 其他错误（如 ECONNREFUSED, ETIMEDOUT 等），记录但不一定失败
            // 这些错误可能表示 SYN 包已发送但连接被拒绝或超时
            if (errno == EPERM || errno == EACCES || errno == ENETUNREACH || errno == EHOSTUNREACH ||
                errno == EADDRNOTAVAIL || errno == ENOBUFS || errno == ENOMEM) {
                if (out_errno) *out_errno = errno;
                if (out_failed_op) *out_failed_op = "connect";
                fcntl(tcp_socket, F_SETFL, flags);
                return -1;
            }
        }
    } else if (connect_result == 0) {
        // 连接立即成功（不太可能，因为目标端口可能关闭）
    }
    
    fcntl(tcp_socket, F_SETFL, flags);
    
    if (send_time) {
        *send_time = get_current_timestamp_ms();
    }
    
    // connect 失败是预期的（TTL 过期或端口关闭），我们通过错误队列接收 ICMP 错误
    // 即使 connect() 返回错误，SYN 包可能已经发送，等待一段时间确保包发送
    usleep(MTR_TCP_SEND_OVERHEAD_US); // 确保 SYN 包发送
    
    return 0;
}

// 解析 ICMP 响应（从 socket 接收，SOCK_DGRAM 方式直接是 ICMP 包）
// 注意：参数名 icmp_identifier 避免与系统宏 icmp_id 冲突
static int parse_icmp_response(const char *buffer, size_t buffer_len, int is_ipv6,
                                int *original_ttl, int *original_seq, int *is_echo_reply,
                                uint16_t *icmp_identifier) {
    if (!buffer || buffer_len < sizeof(struct mtr_icmphdr)) return -1;
    
    // 有些平台（特别是 macOS/iOS 的 SOCK_DGRAM ICMP）返回的数据可能包含 IP 头
    // 检测并跳过 IP 头，只解析 ICMP 部分
    const char *icmp_base = buffer;
    size_t icmp_len = buffer_len;
    uint8_t first_byte = (uint8_t)buffer[0];
    uint8_t ip_version = (first_byte >> 4) & 0x0F;
    
    if (ip_version == 4 && buffer_len >= sizeof(struct ip)) {
        const struct ip *ip_hdr = (const struct ip *)buffer;
        size_t ip_hdr_len = ip_hdr->ip_hl * 4;
        if (ip_hdr_len >= 20 && ip_hdr_len <= buffer_len && buffer_len >= ip_hdr_len + sizeof(struct mtr_icmphdr)) {
            icmp_base = buffer + ip_hdr_len;
            icmp_len = buffer_len - ip_hdr_len;
            if (original_ttl) *original_ttl = ip_hdr->ip_ttl; // 保存原始 TTL
        }
    } else if (ip_version == 6 && buffer_len >= 40) {
        size_t ip6_hdr_len = 40; // 固定长度
        if (buffer_len >= ip6_hdr_len + sizeof(struct mtr_icmphdr)) {
            icmp_base = buffer + ip6_hdr_len;
            icmp_len = buffer_len - ip6_hdr_len;
            if (original_ttl) *original_ttl = buffer[7]; // IPv6 Hop Limit 在偏移7
        }
    }
    
    if (icmp_len < sizeof(struct mtr_icmphdr)) {
        return -1;
    }
    
    const struct mtr_icmphdr *icmp_hdr = (const struct mtr_icmphdr *)icmp_base;
    
    // ICMP 类型常量
    uint8_t echo_reply_type = is_ipv6 ? 129 : 0;  // ICMP6_ECHO_REPLY : ICMP_ECHOREPLY
    uint8_t time_exceeded_type = is_ipv6 ? 3 : 11;  // ICMP6_TIME_EXCEEDED : ICMP_TIME_EXCEEDED
    uint8_t dest_unreach_type = is_ipv6 ? 1 : 3;  // ICMP6_DST_UNREACH : ICMP_DEST_UNREACH
    
    if (icmp_hdr->type == echo_reply_type) {
        // ICMP Echo Reply
        if (is_echo_reply) *is_echo_reply = 1;
        // 提取 ID 和序列号（使用直接内存访问避免结构体成员访问问题）
        // ICMP 头布局：type(1) + code(1) + checksum(2) + id(2) + sequence(2)
        const uint16_t *id_ptr = (const uint16_t *)(icmp_base + 4);  // 偏移 4 字节
        const uint16_t *seq_ptr = (const uint16_t *)(icmp_base + 6);  // 偏移 6 字节
        uint16_t id_value = ntohs(*id_ptr);
        uint16_t seq_value = ntohs(*seq_ptr);
        if (icmp_identifier) *icmp_identifier = id_value;
        if (original_seq) *original_seq = seq_value;
        if (original_ttl) *original_ttl = 0;  // Echo Reply 无法获取原始 TTL
        return 0;
    } else if (icmp_hdr->type == time_exceeded_type || icmp_hdr->type == dest_unreach_type) {
        // ICMP Time Exceeded 或 Destination Unreachable
        if (is_echo_reply) *is_echo_reply = 0;
        // 解析原始 IP 头和数据
        if (icmp_len < 8 + 1) {
            return -1;
        }
        
        const uint8_t *ip_version_byte = (const uint8_t *)(icmp_base + 8);
        uint8_t ip_version = (*ip_version_byte >> 4) & 0x0F;
        
        size_t orig_ip_hdr_len = 0;
        if (ip_version == 4) {
            if (icmp_len < 8 + sizeof(struct ip)) return -1;
            const struct ip *orig_ip = (const struct ip *)(icmp_base + 8);
            orig_ip_hdr_len = orig_ip->ip_hl * 4;
            if (orig_ip_hdr_len < 20 || orig_ip_hdr_len > 60) orig_ip_hdr_len = 20;
            if (original_ttl) *original_ttl = orig_ip->ip_ttl;
        } else if (ip_version == 6) {
            orig_ip_hdr_len = 40;
            if (icmp_len < 8 + 40) return -1;
            if (original_ttl) *original_ttl = ((const uint8_t *)(icmp_base + 8))[7];
        } else {
            return -1;
        }
        
        // 检查原始包是否是 ICMP Echo Request
        if (icmp_len >= 8 + orig_ip_hdr_len + sizeof(struct mtr_icmphdr)) {
            const struct mtr_icmphdr *orig_icmp = (const struct mtr_icmphdr *)(icmp_base + 8 + orig_ip_hdr_len);
            uint8_t echo_request_type = is_ipv6 ? 128 : 8;
            if (orig_icmp->type == echo_request_type) {
                // 使用直接内存访问
                const char *orig_icmp_base = icmp_base + 8 + orig_ip_hdr_len;
                const uint16_t *id_ptr = (const uint16_t *)(orig_icmp_base + 4);
                const uint16_t *seq_ptr = (const uint16_t *)(orig_icmp_base + 6);
                uint16_t id_value = ntohs(*id_ptr);
                uint16_t seq_value = ntohs(*seq_ptr);
                if (icmp_identifier) *icmp_identifier = id_value;
                if (original_seq) *original_seq = seq_value;
                return 0;
            }
        }
        
        // 检查原始包是否是 UDP
        if (icmp_len >= 8 + orig_ip_hdr_len + 8) {  // UDP 头至少 8 字节
            const struct udphdr *orig_udp = (const struct udphdr *)(icmp_base + 8 + orig_ip_hdr_len);
            uint16_t dst_port = ntohs(orig_udp->uh_dport);
            if (dst_port >= MTR_DST_PORT_BASE && dst_port < MTR_DST_PORT_BASE + 256) {
                int extracted_ttl = dst_port - MTR_DST_PORT_BASE;
                if (extracted_ttl >= 1 && extracted_ttl <= 255) {
                    if (original_ttl) *original_ttl = extracted_ttl;
                    if (original_seq) *original_seq = extracted_ttl;  // 使用 TTL 作为序列号
                    return 0;
                }
            }
        }
        
        // 检查原始包是否是 TCP（使用数组方式读取端口，避免需要完整的 TCP 头）
        if (icmp_len >= 8 + orig_ip_hdr_len + 8) {
            const uint16_t *tcp_ports = (const uint16_t *)(icmp_base + 8 + orig_ip_hdr_len);
            uint16_t dst_port = ntohs(tcp_ports[1]);  // TCP 目标端口在偏移 2 的位置
            if (dst_port == MTR_TCP_DST_PORT) {
                // TCP 协议，无法从端口提取 TTL，返回 -1 让调用者使用其他方式匹配
                return -1;
            }
        }
    }
    
    return -1;
}

// 接收 ICMP 响应（完整实现）
static int receive_icmp_response(socket_t sock, int timeout_ms, const char *target_ip, 
                                 int ttl, int is_ipv6, double *rtt_out, char *src_ip_out,
                                 uint64_t send_time, uint16_t expected_id) {
    if (sock < 0 || !target_ip || !rtt_out) return -1;
    
    
    uint64_t start_time = get_current_timestamp_ms();
    uint16_t expected_id_host = (expected_id != 0) ? ntohs(expected_id) : 0;
    
    // 循环接收，直到超时或收到匹配的响应
    while (1) {
        // 检查是否超时
        uint64_t current_time = get_current_timestamp_ms();
        uint64_t elapsed = current_time - start_time;
        if (elapsed >= (uint64_t)timeout_ms) {
            return -1; // 超时
        }
        
        // 使用 select 等待数据可读
        fd_set read_fds;
        FD_ZERO(&read_fds);
        FD_SET(sock, &read_fds);
        
        int remaining_timeout = timeout_ms - (int)elapsed;
        struct timeval timeout;
        timeout.tv_sec = remaining_timeout / 1000;
        timeout.tv_usec = (remaining_timeout % 1000) * 1000;
        
        int result = select(sock + 1, &read_fds, NULL, NULL, &timeout);
        if (result <= 0 || !FD_ISSET(sock, &read_fds)) {
            return -1; // 超时或错误
        }
        
        // 接收数据包
        char buffer[MTR_RECV_BUFFER_SIZE];
        struct sockaddr_storage from_addr;
        socklen_t from_len = sizeof(from_addr);
        
        ssize_t bytes_received = recvfrom(sock, buffer, sizeof(buffer), 0,
                                          (struct sockaddr *)&from_addr, &from_len);
        if (bytes_received < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                continue; // 暂时没有数据，继续等待
            }
            continue; // 其他错误，继续接收
        }
        
        if (bytes_received < (ssize_t)sizeof(struct mtr_icmphdr)) {
            continue; // 数据包太小，继续接收
        }
        
        uint64_t receive_time = get_current_timestamp_ms();
        
        // 提取源 IP 地址
        char temp_src_ip[INET6_ADDRSTRLEN] = {0};
        if (from_addr.ss_family == AF_INET6) {
            struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)&from_addr;
            inet_ntop(AF_INET6, &addr6->sin6_addr, temp_src_ip, INET6_ADDRSTRLEN);
        } else if (from_addr.ss_family == AF_INET) {
            struct sockaddr_in *addr4 = (struct sockaddr_in *)&from_addr;
            inet_ntop(AF_INET, &addr4->sin_addr, temp_src_ip, INET6_ADDRSTRLEN);
        } else {
            continue; // 不支持的地址族，继续接收
        }
           
        // 解析 ICMP 响应
        int original_ttl = 0;
        int original_seq = 0;
        int is_echo_reply = 0;
        uint16_t icmp_id_value = 0;
        
        if (parse_icmp_response(buffer, (size_t)bytes_received, is_ipv6,
                               &original_ttl, &original_seq, &is_echo_reply, &icmp_id_value) != 0) {
            continue; // 解析失败，继续接收
        }
        
        // 验证 ICMP ID（可选验证，因为内核可能改写 ID）预留功能
        // 注意：在 iOS/macOS 上使用 SOCK_DGRAM 时，内核会自动管理 ICMP ID
        // 如果 expected_id_host 为 0，则不验证 ID（主要依赖序列号匹配）
        if (expected_id_host != 0 && icmp_id_value != 0) {
            // 可选：如果提供了期望的 ID，可以验证，但不作为必要条件
            // 因为 NAT/内核可能改写 ID，所以这里不强制要求匹配
            if (icmp_id_value != expected_id_host) {
            }
        }
        
        // 验证序列号/TTL。优先使用嵌入的 UDP 目的端口解出的 TTL（original_seq）。
        // 部分设备返回的 ICMP 可能只携带 IP 头中的 TTL（original_ttl）或序列号为 0。
        // 匹配策略：seq==ttl 或 ttl==original_ttl（两者其一即可）。
        if (original_seq != ttl) {
            if (original_ttl != ttl) {
                continue; // 序列号和 TTL 都不匹配，继续接收
            }
        }
        
        // 匹配成功，计算 RTT
        if (send_time > 0 && receive_time > send_time) {
            *rtt_out = (double)(receive_time - send_time);
        } else {
            *rtt_out = 0.0;
        }
        
        // 复制源 IP
        if (src_ip_out) {
            safe_strncpy(src_ip_out, temp_src_ip, INET6_ADDRSTRLEN);
        }
        
        return 0;
    }
}

// 接收 UDP 错误消息（从错误队列接收 ICMP Time Exceeded/Destination Unreachable）
// recv_icmp_sock: 可选的 ICMP DGRAM socket，用于接收 ICMP 错误/Time Exceeded
static __attribute__((unused)) int receive_udp_error(socket_t udp_sock, socket_t recv_icmp_sock, int timeout_ms, const char *target_ip,
                            int ttl, int is_ipv6, double *rtt_out, char *src_ip_out,
                            uint64_t send_time) {
    if (udp_sock < 0 || !target_ip || !rtt_out) return -1;
    
    
    // 优先尝试通过独立的 ICMP socket 接收 ICMP 错误/Time Exceeded
    if (recv_icmp_sock >= 0) {
        double icmp_rtt = -1.0;
        char icmp_src_ip[INET6_ADDRSTRLEN] = {0};
        // 使用与 UDP 相同的超时，匹配序列号=TTL，不校验 ID
        int icmp_res = receive_icmp_response(recv_icmp_sock, timeout_ms, target_ip, ttl, is_ipv6,
                                             &icmp_rtt, icmp_src_ip, send_time, 0);
        if (icmp_res == 0 && icmp_src_ip[0] != '\0') {
            if (rtt_out) *rtt_out = icmp_rtt;
            if (src_ip_out) safe_strncpy(src_ip_out, icmp_src_ip, INET6_ADDRSTRLEN);
            return 0;
        }
    }

    // 设置 IP_RECVERR 选项以接收 ICMP 错误消息（iOS 可能不支持，但不影响功能）
    int recverr = 1;
    if (is_ipv6) {
        if (setsockopt(udp_sock, IPPROTO_IPV6, IPV6_RECVERR, &recverr, sizeof(recverr)) < 0) {
        }
    } else {
        if (setsockopt(udp_sock, IPPROTO_IP, IP_RECVERR, &recverr, sizeof(recverr)) < 0) {
        }
    }
    // 注意：即使设置失败，iOS 内核仍可能传递 ICMP 错误消息
    
    fd_set read_fds, except_fds;
    FD_ZERO(&read_fds);
    FD_ZERO(&except_fds);
    FD_SET(udp_sock, &read_fds);
    FD_SET(udp_sock, &except_fds);
    
    struct timeval timeout;
    timeout.tv_sec = timeout_ms / 1000;
    timeout.tv_usec = (timeout_ms % 1000) * 1000;
    
    int result = select(udp_sock + 1, &read_fds, NULL, &except_fds, &timeout);
    if (result <= 0) {
        // 超时：MTR 使用 UDP 时只应该收到 ICMP 错误消息，不应该收到正常的 UDP 响应
        return -1;
    }
    
    // 从错误队列接收 ICMP 错误消息
    // 注意：iOS 上可能不支持 MSG_ERRQUEUE，尝试使用普通接收方式
    char data_buffer[MTR_RECV_BUFFER_SIZE];
    struct sockaddr_storage from_addr;
    socklen_t from_len = sizeof(from_addr);
    
    ssize_t bytes_received = recvfrom(udp_sock, data_buffer, sizeof(data_buffer), MSG_DONTWAIT,
                                     (struct sockaddr *)&from_addr, &from_len);
    if (bytes_received < 0) {
        // 如果普通接收失败，尝试使用 recvmsg（iOS 可能不支持错误队列）
        char control_buffer[256];
        struct iovec iov;
        struct msghdr msg;
        
        memset(&msg, 0, sizeof(msg));
        iov.iov_base = data_buffer;
        iov.iov_len = sizeof(data_buffer);
        msg.msg_iov = &iov;
        msg.msg_iovlen = 1;
        msg.msg_control = control_buffer;
        msg.msg_controllen = sizeof(control_buffer);
        msg.msg_name = &from_addr;
        msg.msg_namelen = sizeof(from_addr);
        
        bytes_received = recvmsg(udp_sock, &msg, MSG_DONTWAIT);
        if (bytes_received < 0) {
            return -1;
        }
        
        // 尝试从控制消息解析源 IP（iOS 可能不支持）
        for (struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg); cmsg != NULL; cmsg = CMSG_NXTHDR(&msg, cmsg)) {
            if ((is_ipv6 && cmsg->cmsg_level == IPPROTO_IPV6) ||
                (!is_ipv6 && cmsg->cmsg_level == IPPROTO_IP)) {
                // 尝试解析控制消息
                if (cmsg->cmsg_len >= sizeof(struct sock_extended_err)) {
                    struct sock_extended_err *serr = (struct sock_extended_err *)CMSG_DATA(cmsg);
                    if (serr && (serr->ee_origin == SO_EE_ORIGIN_ICMP || serr->ee_origin == SO_EE_ORIGIN_ICMP6)) {
                        // 从控制消息中提取源地址
                        if (cmsg->cmsg_len >= CMSG_LEN(sizeof(struct sockaddr_in)) && !is_ipv6) {
                            struct sockaddr_in *sin = (struct sockaddr_in *)(CMSG_DATA(cmsg) + sizeof(struct sock_extended_err));
                            if (src_ip_out) {
                                inet_ntop(AF_INET, &sin->sin_addr, src_ip_out, INET6_ADDRSTRLEN);
                            }
                        } else if (cmsg->cmsg_len >= CMSG_LEN(sizeof(struct sockaddr_in6)) && is_ipv6) {
                            struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)(CMSG_DATA(cmsg) + sizeof(struct sock_extended_err));
                            if (src_ip_out) {
                                inet_ntop(AF_INET6, &sin6->sin6_addr, src_ip_out, INET6_ADDRSTRLEN);
                            }
                        }
                    }
                }
            }
        }
    } else {
        // 普通 recvfrom 成功，从 from_addr 提取源 IP
        if (src_ip_out) {
            if (from_addr.ss_family == AF_INET6) {
                struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)&from_addr;
                inet_ntop(AF_INET6, &addr6->sin6_addr, src_ip_out, INET6_ADDRSTRLEN);
            } else if (from_addr.ss_family == AF_INET) {
                struct sockaddr_in *addr4 = (struct sockaddr_in *)&from_addr;
                inet_ntop(AF_INET, &addr4->sin_addr, src_ip_out, INET6_ADDRSTRLEN);
            }
        }
    }
    
    
    // 解析 ICMP 错误消息
    int original_ttl = 0;
    int original_seq = 0;
    int is_echo_reply = 0;
    uint16_t icmp_id_value = 0;
    
    if (parse_icmp_response(data_buffer, (size_t)bytes_received, is_ipv6,
                           &original_ttl, &original_seq, &is_echo_reply, &icmp_id_value) != 0) {
        return -1;
    }
    
    // 验证 TTL（对于 UDP，从目标端口提取的 TTL 应该匹配）
    if (original_ttl != ttl && original_seq != ttl) {
        return -1;
    }
    
    // 计算 RTT
    uint64_t receive_time = get_current_timestamp_ms();
    *rtt_out = (double)(receive_time - send_time);
    
    return 0;
}

// 接收 TCP 错误消息（从错误队列接收 ICMP Time Exceeded/Destination Unreachable）
static __attribute__((unused)) int receive_tcp_error(socket_t tcp_sock, int timeout_ms, const char *target_ip,
                             int ttl, int is_ipv6, double *rtt_out, char *src_ip_out,
                             uint16_t src_port, uint64_t send_time) {
    if (tcp_sock < 0 || !target_ip || !rtt_out) return -1;
    
    // 设置 IP_RECVERR 选项（iOS 可能不支持，但不影响功能）
    int recverr = 1;
    if (is_ipv6) {
        setsockopt(tcp_sock, IPPROTO_IPV6, IPV6_RECVERR, &recverr, sizeof(recverr));
    } else {
        setsockopt(tcp_sock, IPPROTO_IP, IP_RECVERR, &recverr, sizeof(recverr));
    }
    
    fd_set read_fds, except_fds;
    FD_ZERO(&read_fds);
    FD_ZERO(&except_fds);
    FD_SET(tcp_sock, &read_fds);
    FD_SET(tcp_sock, &except_fds);
    
    struct timeval timeout;
    timeout.tv_sec = timeout_ms / 1000;
    timeout.tv_usec = (timeout_ms % 1000) * 1000;
    
    int result = select(tcp_sock + 1, &read_fds, NULL, &except_fds, &timeout);
    if (result <= 0) {
        return -1;
    }
    
    // 从错误队列接收（iOS 可能不支持 MSG_ERRQUEUE，使用普通接收方式）
    char data_buffer[MTR_RECV_BUFFER_SIZE];
    struct sockaddr_storage from_addr;
    socklen_t from_len = sizeof(from_addr);
    
    ssize_t bytes_received = recvfrom(tcp_sock, data_buffer, sizeof(data_buffer), MSG_DONTWAIT,
                                     (struct sockaddr *)&from_addr, &from_len);
    if (bytes_received < 0) {
        // 尝试使用 recvmsg
        char control_buffer[256];
        struct iovec iov;
        struct msghdr msg;
        
        memset(&msg, 0, sizeof(msg));
        iov.iov_base = data_buffer;
        iov.iov_len = sizeof(data_buffer);
        msg.msg_iov = &iov;
        msg.msg_iovlen = 1;
        msg.msg_control = control_buffer;
        msg.msg_controllen = sizeof(control_buffer);
        msg.msg_name = &from_addr;
        msg.msg_namelen = sizeof(from_addr);
        
        bytes_received = recvmsg(tcp_sock, &msg, MSG_DONTWAIT);
        if (bytes_received < 0) {
            return -1;
        }
        
        // 尝试从控制消息解析源 IP
        for (struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg); cmsg != NULL; cmsg = CMSG_NXTHDR(&msg, cmsg)) {
            if ((is_ipv6 && cmsg->cmsg_level == IPPROTO_IPV6) ||
                (!is_ipv6 && cmsg->cmsg_level == IPPROTO_IP)) {
                if (cmsg->cmsg_len >= sizeof(struct sock_extended_err)) {
                    struct sock_extended_err *serr = (struct sock_extended_err *)CMSG_DATA(cmsg);
                    if (serr && (serr->ee_origin == SO_EE_ORIGIN_ICMP || serr->ee_origin == SO_EE_ORIGIN_ICMP6)) {
                        if (cmsg->cmsg_len >= CMSG_LEN(sizeof(struct sockaddr_in)) && !is_ipv6) {
                            struct sockaddr_in *sin = (struct sockaddr_in *)(CMSG_DATA(cmsg) + sizeof(struct sock_extended_err));
                            if (src_ip_out) {
                                inet_ntop(AF_INET, &sin->sin_addr, src_ip_out, INET6_ADDRSTRLEN);
                            }
                        } else if (cmsg->cmsg_len >= CMSG_LEN(sizeof(struct sockaddr_in6)) && is_ipv6) {
                            struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)(CMSG_DATA(cmsg) + sizeof(struct sock_extended_err));
                            if (src_ip_out) {
                                inet_ntop(AF_INET6, &sin6->sin6_addr, src_ip_out, INET6_ADDRSTRLEN);
                            }
                        }
                    }
                }
            }
        }
    } else {
        // 从 from_addr 提取源 IP
        if (src_ip_out) {
            if (from_addr.ss_family == AF_INET6) {
                struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)&from_addr;
                inet_ntop(AF_INET6, &addr6->sin6_addr, src_ip_out, INET6_ADDRSTRLEN);
            } else if (from_addr.ss_family == AF_INET) {
                struct sockaddr_in *addr4 = (struct sockaddr_in *)&from_addr;
                inet_ntop(AF_INET, &addr4->sin_addr, src_ip_out, INET6_ADDRSTRLEN);
            }
        }
    }
    
    // 解析 ICMP 错误消息（TCP 协议需要从源端口匹配，这里简化处理）
    // 实际实现中需要更复杂的匹配逻辑
    
    // 计算 RTT
    uint64_t receive_time = get_current_timestamp_ms();
    *rtt_out = (double)(receive_time - send_time);
    
    return 0;
}

// ICMP 并行探测：启动 worker 线程
static int icmp_parallel_worker_start(icmp_parallel_worker_ctx *ctx, socket_t sock, 
                                      mtr_event_queue *queue, int is_ipv6,
                                      int max_ttl, int times, uint16_t seq_xor_token) {
    if (!ctx || sock < 0 || !queue) return -1;
    
    pthread_mutex_lock(&ctx->mutex);
    if (ctx->running) {
        pthread_mutex_unlock(&ctx->mutex);
        return 0;
    }
    
    ctx->sock = sock;
    ctx->event_queue = queue;
    ctx->is_ipv6 = is_ipv6;
    ctx->max_ttl = max_ttl;
    ctx->times = times;
    ctx->seq_xor_token = seq_xor_token;
    ctx->stop = 0;
    
    int ret = pthread_create(&ctx->thread, NULL, icmp_parallel_worker_thread, ctx);
    if (ret != 0) {
        ctx->sock = -1;
        pthread_mutex_unlock(&ctx->mutex);
        return -1;
    }
    
    ctx->running = 1;
    pthread_mutex_unlock(&ctx->mutex);
    return 0;
}

// ICMP 并行探测：停止 worker 线程
static void icmp_parallel_worker_stop(icmp_parallel_worker_ctx *ctx) {
    if (!ctx) return;
    
    pthread_mutex_lock(&ctx->mutex);
    if (!ctx->running) {
        pthread_mutex_unlock(&ctx->mutex);
        return;
    }
    
    ctx->stop = 1;
    pthread_mutex_unlock(&ctx->mutex);
    
    pthread_join(ctx->thread, NULL);
    
    pthread_mutex_lock(&ctx->mutex);
    ctx->running = 0;
    ctx->sock = -1;
    pthread_mutex_unlock(&ctx->mutex);
}

// ICMP 并行探测主函数
static int probe_icmp_parallel(const char *target_ip, int max_ttl, int times, 
                               int timeout_ms, int is_ipv6, socket_t icmp_socket,
                               cls_mtr_path_result *path) {
    if (!target_ip || icmp_socket < 0 || !path) return -1;
    
    // 初始化 session
    mtr_icmp_parallel_session session;
    memset(&session, 0, sizeof(session));
    session.target_ip = target_ip;
    session.is_ipv6 = is_ipv6;
    session.max_ttl = max_ttl;
    session.times = times;
    session.timeout_ms = timeout_ms;
    session.icmp_socket = icmp_socket;
    session.session_start_time = get_current_timestamp_ms();
    session.target_reached = 0;  // 初始化为未到达目标
    session.target_reached_ttl = 0;
    // session token：不依赖 ICMP ID（可能被内核改写），而是对 seq 做 XOR 编码
    // 目标：让“属于本次 run”的判定更强，过滤噪声 ICMP 报文
    uint64_t token_seed = session.session_start_time ^ (uint64_t)getpid() ^ (uint64_t)(uintptr_t)&session;
    session.seq_xor_token = (uint16_t)(token_seed & 0xFFFF);
    if (session.seq_xor_token == 0) session.seq_xor_token = 0xA5A5;
    int consecutive_timeout_stopped = 0;  // 是否因为连续超时而停止
    int deadline_hit = 0;                // 是否触发全局超时（未到达目标时应视为失败）
    int fatal_error_code = 0;            // 返回 cls_mtr_detector_error_code（负值）或 0

    // 动态分配 hops（避免大对象放栈上导致栈溢出）
    session.hops = mtr_alloc_hops_for_max_ttl(max_ttl);
    if (!session.hops) {
        return -1;
    }
    
    // 计算 session 全局 deadline（绝对时间戳）
    // 注意：最后一跳可能使用更慢的 MTR_TARGET_PROBE_GAP_US（防止 rate-limit），因此 deadline 估算要取更保守的 gap
    uint32_t worst_gap_us = MTR_PROBE_GAP_US;
    if (MTR_TARGET_PROBE_GAP_US > worst_gap_us) worst_gap_us = MTR_TARGET_PROBE_GAP_US;
    const uint64_t session_timeout_ms = mtr_compute_parallel_session_timeout_ms(max_ttl, times, timeout_ms, worst_gap_us);
    const uint64_t deadline_ms = session.session_start_time + session_timeout_ms;
    
    // 初始化事件队列（按 max_ttl*times 预估容量，必要时自动扩容）
    mtr_event_queue event_queue;
    int event_queue_capacity = mtr_compute_event_queue_capacity(max_ttl, times);
    if (event_queue_init(&event_queue, event_queue_capacity) != 0) {
        free(session.hops);
        session.hops = NULL;
        return -1;
    }
    session.event_queue = &event_queue;
    
    // 初始化所有 hop 状态
    for (int ttl = 1; ttl <= max_ttl; ttl++) {
        session.hops[ttl].first_send_time = 0;
        session.hops[ttl].sent_count = 0;
        session.hops[ttl].recv_count = 0;
        session.hops[ttl].ttl_done = 0;
    }
    
    // 启动并行 worker 线程
    icmp_parallel_worker_ctx worker_ctx = {
        .mutex = PTHREAD_MUTEX_INITIALIZER,
        .running = 0,
        .stop = 0,
        .sock = -1
    };
    
    if (icmp_parallel_worker_start(&worker_ctx, icmp_socket, &event_queue, is_ipv6,
                                   max_ttl, times, session.seq_xor_token) != 0) {
        event_queue_destroy(&event_queue);
        if (session.hops) {
            free(session.hops);
            session.hops = NULL;
        }
        return -1;
    }
    
    // 使用进程 ID 和时间戳生成非 0 的 ICMP ID，避免 ID=0 可能导致某些包被过滤的问题
    // 注意：在 iOS/macOS 上使用 SOCK_DGRAM 时，内核可能会改写此 ID，但使用非 0 值作为基础更安全
    uint16_t icmp_identifier = (uint16_t)((getpid() ^ (uint16_t)(get_current_timestamp_ms() & 0xFFFF)) & 0xFFFF);
    if (icmp_identifier == 0) {
        icmp_identifier = 1;  // 确保不为 0
    }
    int last_set_ttl = 0;  // 上次设置的 TTL，用于优化 setsockopt 调用
    
    // 主循环：状态机
    while (1) {
        uint64_t current_time = get_current_timestamp_ms();
        
        // 检查全局超时：如果没到达目标则认为探测失败（但仍会返回已采样的部分结果）
        if (current_time > deadline_ms) {
            deadline_hit = 1;
            break;
        }
        
        // 1. 处理事件队列中的所有事件
        mtr_icmp_event event;
        while (event_queue_try_pop(&event_queue, &event) == 0) {
            int ttl = event.ttl;
            if (ttl < 1 || ttl > max_ttl) continue;
            
            mtr_hop_state *hop = &session.hops[ttl];
            
            int matched = 0;
            int match_idx = -1;
            double rtt = 0.0;
            
            // 如果事件中包含有效的 probe_index，直接使用
            // 检查条件：probe_index 在有效范围内，且 send_times 已设置（说明该探测已发送）
            if (event.probe_index >= 0 && event.probe_index < times && 
                hop->send_times[event.probe_index] > 0) {
                // 直接匹配指定的 probe_index
                if (hop->rtts[event.probe_index] == 0.0 && hop->src_ips[event.probe_index][0] == '\0') {
                    rtt = (double)(event.recv_time - hop->send_times[event.probe_index]);
                    if (rtt > 0 && rtt < 60000) {  // 合理的 RTT 范围
                        match_idx = event.probe_index;
                    }
                }
            } else {
                // 如果没有 probe_index，使用时间窗口匹配：找到最接近的未匹配的发送时间
                int best_match_idx = -1;
                double best_rtt = 0.0;
                for (int i = 0; i < hop->sent_count && i < times; i++) {
                    if (hop->rtts[i] == 0.0 && hop->src_ips[i][0] == '\0') {
                        // 计算 RTT
                        double calculated_rtt = (double)(event.recv_time - hop->send_times[i]);
                        if (calculated_rtt > 0 && calculated_rtt < 60000) {  // 合理的 RTT 范围
                            // 选择 RTT 最小的匹配（简单策略）
                            if (best_match_idx == -1 || calculated_rtt < best_rtt) {
                                best_match_idx = i;
                                best_rtt = calculated_rtt;
                            }
                        }
                    }
                }
                match_idx = best_match_idx;
                rtt = best_rtt;
            }
            
            // 如果找到匹配，记录结果（确保 IP 不为空）
            if (match_idx >= 0 && event.src_ip[0] != '\0') {
                hop->rtts[match_idx] = rtt;
                safe_strncpy(hop->src_ips[match_idx], event.src_ip, sizeof(hop->src_ips[match_idx]));
                hop->recv_count++;
                matched = 1;
            }
            
            // 检查是否到达目标
            if (strcmp(event.src_ip, target_ip) == 0) {
                if (!session.target_reached) {
                    session.target_reached = 1;
                    session.target_reached_ttl = ttl;
                }
                hop->ttl_done = 1;
                // 标记所有更大的 TTL 也完成（不再发送新探测）
                for (int t = ttl + 1; t <= max_ttl; t++) {
                    session.hops[t].ttl_done = 1;
                }
            }
        }
        
        // 2. 批量发送探测包：遍历所有 TTL，对每个需要发送的 TTL 发送探测
        // 策略：一次性快速发送完所有 TTL 的所有探测（每个 TTL 连续发送 times 次）
        // 如果已到达目标，停止发送新的探测，但继续等待已发送探测的响应
        int sent_this_round = 0;
        
        // 如果已到达目标，不再发送新的探测
        if (!session.target_reached) {
            // 遍历所有 TTL
            for (int ttl = 1; ttl <= max_ttl && !session.target_reached && !consecutive_timeout_stopped; ttl++) {
                mtr_hop_state *hop = &session.hops[ttl];
                
                // 检查该 TTL 是否已完成
                if (hop->ttl_done) {
                    continue;
                }
                
                // 在发送当前 TTL 的探测之前，检查之前的 TTL 是否已经连续超时
                if (ttl > 1 && hop->sent_count == 0) {
                    if (mtr_check_consecutive_timeouts_and_stop(session.hops,
                                                                max_ttl,
                                                                times,
                                                                timeout_ms,
                                                                current_time,
                                                                ttl - 1,
                                                                path,
                                                                NULL)) {
                        consecutive_timeout_stopped = 1;
                        break;
                    }
                }
                
                // 检查是否需要发送更多探测
                if (hop->sent_count < times) {
                    // 设置 TTL（只在 TTL 改变时设置，避免频繁调用）
                    if (last_set_ttl != ttl) {
                        int ttl_value = ttl;
                        int so_ret = 0;
                        if (is_ipv6) {
                            so_ret = setsockopt(icmp_socket, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &ttl_value, sizeof(ttl_value));
                        } else {
                            so_ret = setsockopt(icmp_socket, IPPROTO_IP, IP_TTL, &ttl_value, sizeof(ttl_value));
                        }
                        if (so_ret < 0) {
                            int e = errno;
                            path->exceptionNum++;
                            fatal_error_code = (int)mtr_classify_syscall_failure("setsockopt", e);
                            mtr_record_fatal_error(path, "setsockopt", e);
                            for (int t = ttl; t <= max_ttl; t++) {
                                session.hops[t].ttl_done = 1;
                            }
                            consecutive_timeout_stopped = 1;
                            break;
                        }
                        last_set_ttl = ttl;
                    }
                    
                    // 对该 TTL 连续发送所有剩余的探测（快速发送，不等待间隔）
                    // 注意：即使检测到目标到达，也要发送完当前TTL的所有探测
                    // 在发送过程中，每发送几个探测就处理一次事件队列，以便及时检测目标到达
                    int probes_since_event_check = 0;
                    int current_ttl_target_reached = 0;  // 当前TTL是否检测到目标到达
                    while (hop->sent_count < times) {
                        // 如果已到达目标，且不是当前TTL，则停止发送
                        if (session.target_reached && session.target_reached_ttl != ttl) {
                            break;
                        }
                        int probe_idx = hop->sent_count;
        uint64_t send_time = 0;
                        int send_errno = 0;
                        const char *failed_op = NULL;
                        if (send_icmp_echo(icmp_socket, target_ip, ttl, probe_idx, icmp_identifier, session.seq_xor_token, &send_time, &send_errno, &failed_op) == 0) {
                            hop->send_times[probe_idx] = send_time;
                            if (hop->sent_count == 0) {
                                hop->first_send_time = send_time;
                            }
                            hop->sent_count++;
                            sent_this_round++;
                            probes_since_event_check++;
                            
                            // 每发送3个探测，处理一次事件队列，以便及时检测目标到达
                            if (probes_since_event_check >= 3) {
                                probes_since_event_check = 0;
                                // 快速处理事件队列，检查是否到达目标
                                mtr_icmp_event quick_event;
                                int event_processed = 0;
                                while (event_queue_try_pop(&event_queue, &quick_event) == 0 && event_processed < 10) {
                                    int quick_ttl = quick_event.ttl;
                                    if (quick_ttl >= 1 && quick_ttl <= max_ttl) {
                                        mtr_hop_state *quick_hop = &session.hops[quick_ttl];
                                        
                                        // 快速匹配（简化版，确保 IP 不为空）
                                        // 检查条件：probe_index 在有效范围内，且 send_times 已设置（说明该探测已发送）
                                        if (quick_event.probe_index >= 0 && quick_event.probe_index < times && 
                                            quick_hop->send_times[quick_event.probe_index] > 0 &&
                                            quick_event.src_ip[0] != '\0') {
                                            if (quick_hop->rtts[quick_event.probe_index] == 0.0 && 
                                                quick_hop->src_ips[quick_event.probe_index][0] == '\0') {
                                                double quick_rtt = (double)(quick_event.recv_time - quick_hop->send_times[quick_event.probe_index]);
                                                if (quick_rtt > 0 && quick_rtt < 60000) {
                                                    quick_hop->rtts[quick_event.probe_index] = quick_rtt;
                                                    safe_strncpy(quick_hop->src_ips[quick_event.probe_index], 
                                                                quick_event.src_ip, 
                                                                sizeof(quick_hop->src_ips[quick_event.probe_index]));
                                                    quick_hop->recv_count++;
                                                } 
                                            }
                                        } 
                                        
                                        // 检查是否到达目标（确保 IP 不为空）
                                        if (quick_event.src_ip[0] != '\0' && strcmp(quick_event.src_ip, target_ip) == 0) {
                                            if (!session.target_reached) {
                                                session.target_reached = 1;
                                                session.target_reached_ttl = quick_ttl;
                                                if (quick_ttl == ttl) {
                                                    current_ttl_target_reached = 1;
                } else {
                                                }
                                                quick_hop->ttl_done = 1;
                                                // 标记所有更大的 TTL 也完成
                                                for (int t = quick_ttl + 1; t <= max_ttl; t++) {
                                                    session.hops[t].ttl_done = 1;
                                                }
                                                // 如果是其他TTL到达目标，立即停止当前TTL的发送
                                                if (quick_ttl != ttl) {
                                                    break;  // 跳出事件处理循环，然后会跳出发送循环
                                                }
                                            }
                                        }
                                    }
                                    event_processed++;
                                }
                                
                                // 如果其他TTL到达目标，停止当前TTL的发送
                                if (session.target_reached && session.target_reached_ttl != ttl) {
                                    break;
                                }
                            }
                            
                            // 探测发送节奏：适度间隔，降低拥塞/丢包风险，同时避免探测耗时过长
                            if (hop->sent_count < times) {
                                uint32_t gap_us = current_ttl_target_reached ? MTR_TARGET_PROBE_GAP_US : MTR_PROBE_GAP_US;
                                usleep(gap_us);
                            }
                        } else {
                            int e = (send_errno != 0) ? send_errno : errno;
                            path->exceptionNum++;
                            hop->ttl_done = 1;
                            // 对于明显的“不可达/无权限”错误，直接终止整个 session，避免无意义继续发送
                            const char *op = (failed_op && failed_op[0]) ? failed_op : "sendto";
                            if (e != 0) {
                                fatal_error_code = (int)mtr_classify_syscall_failure(op, e);
                            } else {
                                fatal_error_code = (int)cls_mtr_detector_error_send_failed;
                            }
                            if (fatal_error_code != 0) {
                                mtr_record_fatal_error(path, op, e);
                            }
                            // 仅对“明确致命”的错误提前结束；否则继续，让统计反映丢包
                            if (fatal_error_code == cls_mtr_detector_error_permission_denied ||
                                fatal_error_code == cls_mtr_detector_error_network_unreachable ||
                                fatal_error_code == cls_mtr_detector_error_host_unreachable ||
                                fatal_error_code == cls_mtr_detector_error_address_not_available ||
                                fatal_error_code == cls_mtr_detector_error_resource_exhausted) {
                                for (int t = ttl; t <= max_ttl; t++) {
                                    session.hops[t].ttl_done = 1;
                                }
                            }
                            break;  // 发送失败，跳出循环
                        }
                        
                        // 如果其他TTL到达目标，停止当前TTL的发送
                        if (session.target_reached && session.target_reached_ttl != ttl) {
                            break;
                        }
                    }
                    
                    // 该 TTL 的所有探测都已发送
                    if (hop->sent_count >= times) {
                        if (mtr_check_consecutive_timeouts_and_stop(session.hops,
                                                                    max_ttl,
                                                                    times,
                                                                    timeout_ms,
                                                                    current_time,
                                                                    ttl,
                                                                    path,
                                                                    NULL)) {
                            consecutive_timeout_stopped = 1;
                            break;
                        }
                    }
                } else {
                    // 该 TTL 的所有探测都已发送，检查是否超时
                    if (hop->first_send_time > 0) {
                        uint64_t hop_elapsed = current_time - hop->first_send_time;
                        if (hop_elapsed > (uint64_t)timeout_ms) {
                            // 超时：标记完成
                            hop->ttl_done = 1;
                }
            }
                }
                
                if (session.target_reached || consecutive_timeout_stopped) {
                    break;
                }
            }
        }
        
        // 3. 如果已到达目标，检查目标 hop 是否完成，如果完成则立即退出
        if (session.target_reached) {
            mtr_hop_state *target_hop = &session.hops[session.target_reached_ttl];
            if (target_hop->first_send_time > 0) {
                uint64_t elapsed = current_time - target_hop->first_send_time;
                
                // 检查目标 hop 是否完成：
                // 1. 已发送完本 hop 的所有探测（sent_count>=times），且已接收完所有已发送的响应，或者
                // 2. 已发送完本 hop 的所有探测（sent_count>=times），且已超时
                int target_hop_completed = 0;
                if (target_hop->sent_count >= times && target_hop->recv_count >= target_hop->sent_count) {
                    target_hop_completed = 1;
                } else if (target_hop->sent_count >= times && elapsed > (uint64_t)timeout_ms) {
                    target_hop->ttl_done = 1;
                    target_hop_completed = 1;
                }
                
                // 如果目标 hop 已完成，立即退出，不再等待其他 TTL
                if (target_hop_completed) {
                    break;
                }
            }
        }
        
        // 4. 检查所有 TTL 是否都完成（仅在未到达目标时检查）
        if (!session.target_reached) {
            if (mtr_check_consecutive_timeouts_and_stop(session.hops,
                                                        max_ttl,
                                                        times,
                                                        timeout_ms,
                                                        current_time,
                                                        max_ttl,
                                                        path,
                                                        "probe_icmp_parallel")) {
                consecutive_timeout_stopped = 1;
            }
            
            // 如果连续超时导致停止，跳出循环
            if (consecutive_timeout_stopped) {
                break;
            }
            
            int all_done = 1;
            for (int ttl = 1; ttl <= max_ttl; ttl++) {
                mtr_hop_state *hop = &session.hops[ttl];
                if (!hop->ttl_done) {
                    // 检查是否超时
                    if (hop->sent_count > 0) {
                        uint64_t hop_elapsed = current_time - hop->first_send_time;
                        if (hop_elapsed > (uint64_t)timeout_ms) {
                            hop->ttl_done = 1;
                            continue;
                        }
                    }
                    all_done = 0;
        } else {
                    // 记录完成状态
                    if (hop->sent_count > 0) {
                    }
                }
            }
            
            if (all_done) {
                break;
            }
        }
        
        // 5. 短暂休眠，避免 busy loop（同时提高事件消费频率，减少队列堆积）
        usleep(MTR_MAIN_LOOP_SLEEP_US);
    }
    
    // 停止 worker 线程
    icmp_parallel_worker_stop(&worker_ctx);
    
    // 汇总结果到 path->results
    int last_hop = 0;
    for (int ttl = 1; ttl <= max_ttl; ttl++) {
        mtr_hop_state *hop = &session.hops[ttl];
        
        if (ensure_path_results_capacity(path, (size_t)ttl) != 0) {
            break;
        }
        
        cls_mtr_hop_result *hop_result = &path->results[ttl - 1];
        fill_hop_result_from_state(hop_result, hop, ttl, times);
        if (hop->recv_count > 0) last_hop = ttl;
    }
    
    path->lastHop = last_hop;
    event_queue_destroy(&event_queue);
    int target_reached = session.target_reached;
    if (session.hops) {
        free(session.hops);
        session.hops = NULL;
    }
    
    if (fatal_error_code != 0) {
        return fatal_error_code;
    }
    // 未到达目标且触发提前停止（连续超时/全局 deadline），按失败返回（但 path 仍包含已采样的部分结果）
    if (fatal_error_code != 0) {
        return fatal_error_code;
    }
    if (!target_reached && (consecutive_timeout_stopped || deadline_hit)) {
        return (int)cls_mtr_detector_error_timeout;
    }
    
    return 0;
}

// UDP 并行探测主函数（与 ICMP 类似）
static int probe_udp_parallel(const char *target_ip, int max_ttl, int times,
                              int timeout_ms, int is_ipv6, socket_t udp_socket, socket_t icmp_socket,
                              cls_mtr_path_result *path) {
    if (!target_ip || udp_socket < 0 || !path) return -1;
    
    // 初始化 session（与 ICMP 类似）
    mtr_udp_parallel_session session;
    memset(&session, 0, sizeof(session));
    session.target_ip = target_ip;
    session.is_ipv6 = is_ipv6;
    session.max_ttl = max_ttl;
    session.times = times;
    session.timeout_ms = timeout_ms;
    session.udp_socket = udp_socket;
    session.icmp_socket = icmp_socket;
    session.session_start_time = get_current_timestamp_ms();
    session.target_reached = 0;
    session.target_reached_ttl = 0;
    int deadline_hit = 0;
    int fatal_error_code = 0; // 返回 cls_mtr_detector_error_code（负值）或 0
    
    session.hops = mtr_alloc_hops_for_max_ttl(max_ttl);
    if (!session.hops) {
        return -1;
    }
    // 注意：最后一跳可能使用更慢的 MTR_TARGET_PROBE_GAP_US（防止 rate-limit），因此 deadline 估算要取更保守的 gap
    uint32_t worst_gap_us = MTR_PROBE_GAP_US;
    if (MTR_TARGET_PROBE_GAP_US > worst_gap_us) worst_gap_us = MTR_TARGET_PROBE_GAP_US;
    const uint64_t session_timeout_ms = mtr_compute_parallel_session_timeout_ms(max_ttl, times, timeout_ms, worst_gap_us);
    const uint64_t deadline_ms = session.session_start_time + session_timeout_ms;
    
    // 初始化事件队列（按 max_ttl*times 预估容量，必要时自动扩容）
    mtr_udp_event_queue event_queue;
    int event_queue_capacity = mtr_compute_event_queue_capacity(max_ttl, times);
    if (udp_event_queue_init(&event_queue, event_queue_capacity) != 0) {
        free(session.hops);
        session.hops = NULL;
        return -1;
    }
    session.event_queue = &event_queue;
    
    // 初始化所有 hop 状态
    for (int ttl = 1; ttl <= max_ttl; ttl++) {
        session.hops[ttl].first_send_time = 0;
        session.hops[ttl].sent_count = 0;
        session.hops[ttl].recv_count = 0;
        session.hops[ttl].ttl_done = 0;
    }
    
    // 启动并行 worker 线程
    udp_parallel_worker_ctx worker_ctx = {
        .mutex = PTHREAD_MUTEX_INITIALIZER,
        .running = 0,
        .stop = 0,
        .udp_sock = -1,
        .icmp_sock = -1
    };
    
    // UDP 目的端口编码基址：dst_port = base + (ttl<<8) + probe_index
    // base 需要保证 base + ((max_ttl<<8) + (times-1)) <= 65535
    int max_need = (max_ttl << 8) + ((times > 0) ? (times - 1) : 0);
    uint16_t base_min = (uint16_t)MTR_DST_PORT_BASE; // 传统 traceroute 起始端口
    uint16_t base_max = (max_need >= 65535) ? 1 : (uint16_t)(65535 - max_need);
    if (base_max < base_min) {
        base_min = 1024; // 兜底：不依赖传统端口范围
    }
    if (base_max < base_min) {
        base_min = 1;    // 进一步兜底（目的端口不需要特权）
    }
    uint64_t seed = (uint64_t)get_current_timestamp_ms() ^ (uint64_t)getpid();
    uint16_t dst_port_base = base_min;
    if (base_max >= base_min) {
        uint32_t range = (uint32_t)(base_max - base_min + 1);
        // 尽量按 256 对齐，方便观察（范围太小时则不对齐）
        if (range >= 256) {
            uint32_t slots = range / 256;
            if (slots == 0) slots = 1;
            dst_port_base = (uint16_t)(base_min + (uint16_t)((seed % slots) * 256));
            if (dst_port_base > base_max) dst_port_base = base_max;
        } else {
            dst_port_base = (uint16_t)(base_min + (uint16_t)(seed % range));
        }
    }

    if (udp_parallel_worker_start(&worker_ctx, udp_socket, icmp_socket, &event_queue, is_ipv6, dst_port_base) != 0) {
        udp_event_queue_destroy(&event_queue);
        if (session.hops) {
            free(session.hops);
            session.hops = NULL;
        }
        return -1;
    }
    
    int last_set_ttl = 0;
    int consecutive_timeout_stopped = 0;  // 是否因为连续超时而停止
    
    // 主循环：状态机（与 ICMP 相同逻辑）
    while (1) {
        uint64_t current_time = get_current_timestamp_ms();
        if (current_time > deadline_ms) {
            deadline_hit = 1;
            break;
        }
        
        // 1. 处理事件队列
        int events_processed = 0;
        mtr_udp_event event;
        while (udp_event_queue_try_pop(&event_queue, &event) == 0) {
            events_processed++;
            int ttl = event.ttl;
            if (ttl < 1 || ttl > max_ttl) {
                continue;
            }
            
            mtr_hop_state *hop = &session.hops[ttl];
            
            int match_idx = -1;
            double rtt = 0.0;
            
            // 检查条件：probe_index 在有效范围内，且 send_times 已设置（说明该探测已发送）
            if (event.probe_index >= 0 && event.probe_index < times && 
                hop->send_times[event.probe_index] > 0) {
                if (hop->rtts[event.probe_index] == 0.0 && hop->src_ips[event.probe_index][0] == '\0') {
                    double raw_rtt = (double)(event.recv_time - hop->send_times[event.probe_index]);
                    double abs_rtt = raw_rtt >= 0.0 ? raw_rtt : -raw_rtt;
                    if (abs_rtt > 0.0 && abs_rtt < 60000.0) {
                        match_idx = event.probe_index;
                        rtt = abs_rtt;
                    }
                }
            } else {
                // 时间窗口匹配（允许少量时间戳乱序，使用绝对 RTT）
                if (hop->sent_count != 0) {
                    for (int i = 0; i < hop->sent_count && i < times; i++) {
                        if (hop->send_times[i] == 0) {
                            continue;
                        }
                        if (hop->rtts[i] == 0.0 && hop->src_ips[i][0] == '\0') {
                            double raw_rtt = (double)(event.recv_time - hop->send_times[i]);
                            double abs_rtt = raw_rtt >= 0.0 ? raw_rtt : -raw_rtt;
                            if (abs_rtt > 0.0 && abs_rtt < 60000.0) {
                                if (match_idx == -1 || abs_rtt < rtt) {
                                    match_idx = i;
                                    rtt = abs_rtt;
                                }
                            }
                        }
                    }
                }
            }
            
            if (match_idx >= 0 && event.src_ip[0] != '\0') {
                hop->rtts[match_idx] = rtt;
                safe_strncpy(hop->src_ips[match_idx], event.src_ip, sizeof(hop->src_ips[match_idx]));
                hop->recv_count++;
            }
            
            // 检查是否到达目标（确保 IP 不为空）
            if (event.src_ip[0] != '\0' && (strcmp(event.src_ip, target_ip) == 0 || event.is_target_reply)) {
                if (!session.target_reached) {
                    session.target_reached = 1;
                    session.target_reached_ttl = ttl;
                }
                hop->ttl_done = 1;
                for (int t = ttl + 1; t <= max_ttl; t++) {
                    session.hops[t].ttl_done = 1;
                }
            }
        }
        
        // 2. 批量发送探测包（与 ICMP 相同逻辑）
        int sent_this_round = 0;
        
        if (session.target_reached) {
        } else {
            for (int ttl = 1; ttl <= max_ttl && !session.target_reached && !consecutive_timeout_stopped; ttl++) {
                mtr_hop_state *hop = &session.hops[ttl];
                
                if (hop->ttl_done) continue;
                
                // 在发送当前 TTL 的探测之前，检查之前的 TTL 是否已经连续超时
                if (ttl > 1 && hop->sent_count == 0) {
                    if (mtr_check_consecutive_timeouts_and_stop(session.hops,
                                                                max_ttl,
                                                                times,
                                                                timeout_ms,
                                                                current_time,
                                                                ttl - 1,
                                                                path,
                                                                NULL)) {
                        consecutive_timeout_stopped = 1;
                        break;
                    }
                }
                
                if (hop->sent_count < times) {
                    if (last_set_ttl != ttl) {
                        int ttl_value = ttl;
                        int so_ret = 0;
                        if (is_ipv6) {
                            so_ret = setsockopt(udp_socket, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &ttl_value, sizeof(ttl_value));
                        } else {
                            so_ret = setsockopt(udp_socket, IPPROTO_IP, IP_TTL, &ttl_value, sizeof(ttl_value));
                        }
                        if (so_ret < 0) {
                            int e = errno;
                            path->exceptionNum++;
                            fatal_error_code = (int)mtr_classify_syscall_failure("setsockopt", e);
                            mtr_record_fatal_error(path, "setsockopt", e);
                            for (int t = ttl; t <= max_ttl; t++) {
                                session.hops[t].ttl_done = 1;
                            }
                            consecutive_timeout_stopped = 1;
                            break;
                        }
                        last_set_ttl = ttl;
                    }
                    
                    int probes_since_event_check = 0;
                    int current_ttl_target_reached = 0;
                    while (hop->sent_count < times) {
                        if (session.target_reached && session.target_reached_ttl != ttl) {
                            break;
                        }
                        int probe_idx = hop->sent_count;
                        uint64_t send_time = 0;
                        uint16_t src_port = 0;
                        int send_errno = 0;
                        const char *failed_op = NULL;
                        if (send_udp_packet(udp_socket, target_ip, ttl, probe_idx, dst_port_base, &src_port, &send_time, &send_errno, &failed_op) == 0) {
                            hop->send_times[probe_idx] = send_time;
                            if (hop->sent_count == 0) {
                                hop->first_send_time = send_time;
                            }
                            hop->sent_count++;
                            sent_this_round++;
                            probes_since_event_check++;
                            
                            // 每发送3个探测，处理一次事件队列
                            if (probes_since_event_check >= 3) {
                                probes_since_event_check = 0;
                                mtr_udp_event quick_event;
                                int event_processed = 0;
                                while (udp_event_queue_try_pop(&event_queue, &quick_event) == 0 && event_processed < 10) {
                                    int quick_ttl = quick_event.ttl;
                                    if (quick_ttl >= 1 && quick_ttl <= max_ttl) {
                                        mtr_hop_state *quick_hop = &session.hops[quick_ttl];
                                        
                                // 检查条件：probe_index 在有效范围内，且 send_times 已设置（说明该探测已发送）
                                int quick_match_idx = -1;
                                double quick_rtt = 0.0;
                                
                                if (quick_event.probe_index >= 0 && quick_event.probe_index < times && 
                                    quick_hop->send_times[quick_event.probe_index] > 0) {
                                    if (quick_hop->rtts[quick_event.probe_index] == 0.0 && 
                                        quick_hop->src_ips[quick_event.probe_index][0] == '\0') {
                                        double raw_quick_rtt = (double)(quick_event.recv_time - quick_hop->send_times[quick_event.probe_index]);
                                        quick_rtt = raw_quick_rtt >= 0.0 ? raw_quick_rtt : -raw_quick_rtt;
                                        if (quick_rtt > 0.0 && quick_rtt < 60000.0) {
                                            quick_match_idx = quick_event.probe_index;
                                        }
                                    }
                                } else {
                                    // UDP 探测：probe_index 总是 -1，使用时间窗口匹配
                                    if (quick_hop->sent_count > 0) {
                                        for (int i = 0; i < quick_hop->sent_count && i < times; i++) {
                                            if (quick_hop->send_times[i] > 0 && 
                                                quick_hop->rtts[i] == 0.0 && 
                                                quick_hop->src_ips[i][0] == '\0') {
                                                double raw_rtt = (double)(quick_event.recv_time - quick_hop->send_times[i]);
                                                double abs_rtt = raw_rtt >= 0.0 ? raw_rtt : -raw_rtt;
                                                if (abs_rtt > 0.0 && abs_rtt < 60000.0) {
                                                    if (quick_match_idx == -1 || abs_rtt < quick_rtt) {
                                                        quick_match_idx = i;
                                                        quick_rtt = abs_rtt;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                if (quick_match_idx >= 0 && quick_event.src_ip[0] != '\0') {
                                    quick_hop->rtts[quick_match_idx] = quick_rtt;
                                    safe_strncpy(quick_hop->src_ips[quick_match_idx], 
                                                quick_event.src_ip, 
                                                sizeof(quick_hop->src_ips[quick_match_idx]));
                                    quick_hop->recv_count++;
                                }
                                        
                                        if (strcmp(quick_event.src_ip, target_ip) == 0 || quick_event.is_target_reply) {
                                            if (!session.target_reached) {
                                                session.target_reached = 1;
                                                session.target_reached_ttl = quick_ttl;
                                                if (quick_ttl == ttl) {
                                                    current_ttl_target_reached = 1;
                                                }
                                                quick_hop->ttl_done = 1;
                                                for (int t = quick_ttl + 1; t <= max_ttl; t++) {
                                                    session.hops[t].ttl_done = 1;
                                                }
                                                if (quick_ttl != ttl) {
                                                    break;
                                                }
                                            }
                                        }
                                    }
                                    event_processed++;
                                }
                                
                                if (session.target_reached && session.target_reached_ttl != ttl) {
                                    break;
                                }
                            }
                            
                            if (hop->sent_count < times) {
                                uint32_t gap_us = current_ttl_target_reached ? MTR_TARGET_PROBE_GAP_US : MTR_PROBE_GAP_US;
                                usleep(gap_us);
                            }
                        } else {
                            int e = (send_errno != 0) ? send_errno : errno;
                            path->exceptionNum++;
                            hop->ttl_done = 1;
                            if (e != 0) {
                                const char *op = (failed_op && failed_op[0]) ? failed_op : "sendto";
                                fatal_error_code = (int)mtr_classify_syscall_failure(op, e);
                                mtr_record_fatal_error(path, op, e);
                            } else {
                                fatal_error_code = (int)cls_mtr_detector_error_send_failed;
                            }
                            if (fatal_error_code == cls_mtr_detector_error_permission_denied ||
                                fatal_error_code == cls_mtr_detector_error_network_unreachable ||
                                fatal_error_code == cls_mtr_detector_error_host_unreachable ||
                                fatal_error_code == cls_mtr_detector_error_address_not_available ||
                                fatal_error_code == cls_mtr_detector_error_resource_exhausted) {
                                for (int t = ttl; t <= max_ttl; t++) {
                                    session.hops[t].ttl_done = 1;
                                }
                            }
                            break;
                        }
                        
                        if (session.target_reached && session.target_reached_ttl != ttl) {
                            break;
                        }
                    }
                    
                    if (hop->sent_count >= times) {
                        if (mtr_check_consecutive_timeouts_and_stop(session.hops,
                                                                    max_ttl,
                                                                    times,
                                                                    timeout_ms,
                                                                    current_time,
                                                                    ttl,
                                                                    path,
                                                                    NULL)) {
                            consecutive_timeout_stopped = 1;
                            break;
                        }
                    }
                }
                
                if (session.target_reached || consecutive_timeout_stopped) {
                    break;
                }
            }
        }
        
        // 3. 检查完成状态（与 ICMP 相同逻辑）
        if (session.target_reached) {
            int target_ttl = session.target_reached_ttl;
            mtr_hop_state *target_hop = &session.hops[target_ttl];
            
            uint64_t target_elapsed = current_time - target_hop->first_send_time;
            if (target_hop->sent_count >= times && (target_hop->recv_count >= times || target_elapsed > (uint64_t)timeout_ms)) {
                break;
            }
        } else {
            if (mtr_check_consecutive_timeouts_and_stop(session.hops,
                                                        max_ttl,
                                                        times,
                                                        timeout_ms,
                                                        current_time,
                                                        max_ttl,
                                                        path,
                                                        "probe_udp_parallel")) {
                consecutive_timeout_stopped = 1;
                break;
            }
            
            int all_done = 1;
            for (int ttl = 1; ttl <= max_ttl; ttl++) {
                mtr_hop_state *hop = &session.hops[ttl];
                if (!hop->ttl_done && (hop->sent_count < times || 
                    (current_time - hop->first_send_time) < (uint64_t)timeout_ms)) {
                    all_done = 0;
                    break;
                }
            }
            
            if (all_done) {
                break;
            }
        }
        
        usleep(MTR_MAIN_LOOP_SLEEP_US);
    }
    
    // 停止 worker 线程
    udp_parallel_worker_stop(&worker_ctx);
    
    // 汇总结果到 path->results（与 ICMP 相同逻辑）
    int last_hop = 0;
    for (int ttl = 1; ttl <= max_ttl; ttl++) {
        mtr_hop_state *hop = &session.hops[ttl];
        
        if (ensure_path_results_capacity(path, (size_t)ttl) != 0) {
            break;
        }
        
        cls_mtr_hop_result *hop_result = &path->results[ttl - 1];
        fill_hop_result_from_state(hop_result, hop, ttl, times);
        if (hop->recv_count > 0) last_hop = ttl;
    }
    
    path->lastHop = last_hop;
    udp_event_queue_destroy(&event_queue);
    int target_reached = session.target_reached;
    if (session.hops) {
        free(session.hops);
        session.hops = NULL;
    }
    
    if (fatal_error_code != 0) {
        return fatal_error_code;
    }
    if (!target_reached && (consecutive_timeout_stopped || deadline_hit)) {
        return (int)cls_mtr_detector_error_timeout;
    }
    
    return 0;
}

// TCP 并行探测主函数（与 UDP 类似，但使用 TCP sockets）
static int probe_tcp_parallel(const char *target_ip, int max_ttl, int times,
                               int timeout_ms, int is_ipv6, socket_t *tcp_sockets, int tcp_socket_count,
                               socket_t icmp_sock, unsigned int interface_index, cls_mtr_path_result *path) {
    if (!target_ip || !tcp_sockets || tcp_socket_count <= 0 || !path) return -1;
    
    // 初始化 session
    mtr_tcp_parallel_session session;
    memset(&session, 0, sizeof(session));
    session.target_ip = target_ip;
    session.is_ipv6 = is_ipv6;
    session.max_ttl = max_ttl;
    session.times = times;
    session.timeout_ms = timeout_ms;
    session.tcp_sockets = tcp_sockets;
    session.tcp_socket_count = tcp_socket_count;
    session.session_start_time = get_current_timestamp_ms();
    session.target_reached = 0;
    session.target_reached_ttl = 0;
    int consecutive_timeout_stopped = 0;  // 是否因为连续超时而停止
    int deadline_hit = 0;
    int fatal_error_code = 0;            // 返回 cls_mtr_detector_error_code（负值）或 0
    
    session.hops = mtr_alloc_hops_for_max_ttl(max_ttl);
    if (!session.hops) {
        return -1;
    }
    // 注意：最后一跳可能使用更慢的 MTR_TARGET_PROBE_GAP_US（防止 rate-limit），因此 deadline 估算要取更保守的 gap
    // 另外：send_tcp_syn 内部还有固定等待（确保 SYN 发出），也需要计入发送阶段上界，否则可能提前 deadline 导致最后一跳 responseNum 偏小
    uint32_t worst_gap_us = MTR_TCP_PROBE_GAP_US;
    if (MTR_TARGET_PROBE_GAP_US > worst_gap_us) worst_gap_us = MTR_TARGET_PROBE_GAP_US;
    uint32_t worst_per_probe_us = worst_gap_us + MTR_TCP_SEND_OVERHEAD_US;
    const uint64_t session_timeout_ms = mtr_compute_parallel_session_timeout_ms(max_ttl, times, timeout_ms, worst_per_probe_us);
    const uint64_t deadline_ms = session.session_start_time + session_timeout_ms;
    
    // 初始化事件队列（按 max_ttl*times 预估容量，必要时自动扩容）
    mtr_tcp_event_queue event_queue;
    int event_queue_capacity = mtr_compute_event_queue_capacity(max_ttl, times);
    if (tcp_event_queue_init(&event_queue, event_queue_capacity) != 0) {
        free(session.hops);
        session.hops = NULL;
        return -1;
    }
    session.event_queue = &event_queue;
    
    // 初始化所有 hop 状态
    for (int ttl = 1; ttl <= max_ttl; ttl++) {
        session.hops[ttl].first_send_time = 0;
        session.hops[ttl].sent_count = 0;
        session.hops[ttl].recv_count = 0;
        session.hops[ttl].ttl_done = 0;
    }
    
    // 为本次 TCP MTR session 选择一个源端口基址（避免与系统临时端口冲突，并保证空间足够）
    // src_port = base + (ttl<<8) + probe_index
    int max_need = (max_ttl << 8) + 255;
    uint16_t base_min = 40000;
    uint16_t base_max = (uint16_t)(65535 - max_need);
    if (base_max < base_min) base_max = base_min;
    uint64_t seed = (uint64_t)get_current_timestamp_ms() ^ (uint64_t)getpid();
    // 对齐到 256 边界，方便观察（非必须）
    uint16_t src_port_base = (uint16_t)(base_min + (uint16_t)((seed % ((base_max - base_min + 1) / 256 + 1)) * 256));
    if (src_port_base > base_max) src_port_base = base_max;
    
    // 启动并行 worker 线程
    tcp_parallel_worker_ctx worker_ctx = {
        .mutex = PTHREAD_MUTEX_INITIALIZER,
        .running = 0,
        .stop = 0,
        .tcp_sockets = NULL,
        .tcp_socket_count = 0,
        .icmp_sock = -1
    };
    
    if (tcp_parallel_worker_start(&worker_ctx, tcp_sockets, tcp_socket_count, icmp_sock, &event_queue, is_ipv6, target_ip, src_port_base) != 0) {
        tcp_event_queue_destroy(&event_queue);
        if (session.hops) {
            free(session.hops);
            session.hops = NULL;
        }
        return -1;
    }
    
    // 主循环：状态机（与 UDP 相同逻辑）
    while (1) {
        uint64_t current_time = get_current_timestamp_ms();
        if (current_time > deadline_ms) {
            deadline_hit = 1;
            break;
        }
        
        // 1. 处理事件队列
        mtr_tcp_event event;
        while (tcp_event_queue_try_pop(&event_queue, &event) == 0) {
            int ttl = event.ttl;

            // 新的 TCP 模式：事件必须携带可直接匹配的 (ttl, probe_index)
            if (ttl < 1 || ttl > max_ttl) {
                // TTL 无效，跳过
                continue;
            }
            
            // 处理 TTL 在有效范围内的事件（ICMP 错误消息）
            mtr_hop_state *hop = &session.hops[ttl];
            
            int match_idx = -1;
            double rtt = 0.0;
            
            // 检查条件：probe_index 在有效范围内，且 send_times 已设置（说明该探测已发送）
            if (event.probe_index >= 0 && event.probe_index < times && 
                hop->send_times[event.probe_index] > 0) {
                if (hop->rtts[event.probe_index] == 0.0 && hop->src_ips[event.probe_index][0] == '\0') {
                    rtt = (double)(event.recv_time - hop->send_times[event.probe_index]);
                    if (rtt > 0 && rtt < 60000) {
                        match_idx = event.probe_index;
                    }
                }
            } else {
                // probe_index 缺失：丢弃（TCP 端口编码应该保证能解码）
                continue;
            }
            
            if (match_idx >= 0 && event.src_ip[0] != '\0') {
                hop->rtts[match_idx] = rtt;
                safe_strncpy(hop->src_ips[match_idx], event.src_ip, sizeof(hop->src_ips[match_idx]));
                hop->recv_count++;
            }
            
            // 检查是否到达目标（确保 IP 不为空）
            if (event.src_ip[0] != '\0' && (strcmp(event.src_ip, target_ip) == 0 || event.is_target_reply)) {
                if (!session.target_reached) {
                    session.target_reached = 1;
                    session.target_reached_ttl = ttl;
                }
                hop->ttl_done = 1;
                for (int t = ttl + 1; t <= max_ttl; t++) {
                    session.hops[t].ttl_done = 1;
                }
            }
        }
        
        // 2. 批量发送探测包（与 UDP 相同逻辑，但使用 TCP）
        int sent_this_round = 0;
        
        if (!session.target_reached) {
            for (int ttl = 1; ttl <= max_ttl && !session.target_reached && !consecutive_timeout_stopped; ttl++) {
                mtr_hop_state *hop = &session.hops[ttl];
                
                if (hop->ttl_done) continue;
                
                // 在发送当前 TTL 的探测之前，检查之前的 TTL 是否已经连续超时
                if (ttl > 1 && hop->sent_count == 0) {
                    if (mtr_check_consecutive_timeouts_and_stop(session.hops,
                                                                max_ttl,
                                                                times,
                                                                timeout_ms,
                                                                current_time,
                                                                ttl - 1,
                                                                path,
                                                                NULL)) {
                        consecutive_timeout_stopped = 1;
                        break;
                    }
                }
                
                if (hop->sent_count < times) {
                    int probes_since_event_check = 0;
                    int current_ttl_target_reached = 0;
                    while (hop->sent_count < times) {
                        if (session.target_reached && session.target_reached_ttl != ttl) {
                            break;
                        }
                        int probe_idx = hop->sent_count;
                        uint64_t send_time = 0;
                        uint16_t bind_port = (uint16_t)(src_port_base + (uint16_t)((ttl << 8) + (probe_idx & 0xFF)));

                        // 若没有可用并发槽位，先等待 worker 释放或主动回收超时 socket
                        int slot = -1;
                        while (slot < 0) {
                            pthread_mutex_lock(&worker_ctx.mutex);
                            for (int si = 0; si < tcp_socket_count; si++) {
                                if (tcp_sockets[si] < 0) { slot = si; break; }
                            }
                            pthread_mutex_unlock(&worker_ctx.mutex);

                            if (slot >= 0) break;

                            // 回收明显超时的 in-flight sockets（避免占满并发槽位）
                            pthread_mutex_lock(&worker_ctx.mutex);
                            for (int si = 0; si < tcp_socket_count; si++) {
                                socket_t s = tcp_sockets[si];
                                if (s < 0) continue;
                                uint16_t lp = 0;
                                if (is_ipv6) {
                                    struct sockaddr_in6 la6;
                                    socklen_t llen = sizeof(la6);
                                    if (getsockname(s, (struct sockaddr *)&la6, &llen) == 0) lp = ntohs(la6.sin6_port);
                                } else {
                                    struct sockaddr_in la4;
                                    socklen_t llen = sizeof(la4);
                                    if (getsockname(s, (struct sockaddr *)&la4, &llen) == 0) lp = ntohs(la4.sin_port);
                                }
                                int dt = 0, dp = -1;
                                if (lp != 0 && tcp_probe_decode_from_src_port(lp, src_port_base, &dt, &dp) == 0) {
                                    if (dt >= 1 && dt <= max_ttl && dp >= 0 && dp < times) {
                                        mtr_hop_state *hh = &session.hops[dt];
                                        uint64_t st = hh->send_times[dp];
                                        if (st > 0 && hh->rtts[dp] == 0.0 && hh->src_ips[dp][0] == '\0') {
                                            if (current_time - st > (uint64_t)timeout_ms) {
                                                close(s);
                                                tcp_sockets[si] = -1;
                                            }
                                        }
                                    }
                                }
                            }
                            pthread_mutex_unlock(&worker_ctx.mutex);

                            // 让出一点时间等待事件入队/worker 关闭
                            usleep(10000);
                            current_time = get_current_timestamp_ms();
                        }

                        socket_t tcp_sock = create_tcp_probe_socket(is_ipv6, interface_index, bind_port);
                        if (tcp_sock < 0) {
                            path->bindFailed++;
                            path->exceptionNum++;
                            hop->ttl_done = 1;
                            // 端口绑定/资源耗尽/权限等属于“可解释”的致命错误，直接停止 session
                            int e = errno;
                            if (e != 0) {
                                fatal_error_code = (int)mtr_classify_syscall_failure("bind", e);
                                mtr_record_fatal_error(path, "bind", e);
                                for (int t = ttl; t <= max_ttl; t++) {
                                    session.hops[t].ttl_done = 1;
                                }
                                consecutive_timeout_stopped = 1;
                            }
                            break;
                        }

                        // 放入并发槽位，让 worker 监听
                        pthread_mutex_lock(&worker_ctx.mutex);
                        tcp_sockets[slot] = tcp_sock;
                        pthread_mutex_unlock(&worker_ctx.mutex);

                        int send_errno = 0;
                        const char *failed_op = NULL;
                        int send_result = send_tcp_syn(tcp_sock, target_ip, ttl, probe_idx, NULL, &send_time, &send_errno, &failed_op);
                        if (send_result == 0) {
                            hop->send_times[probe_idx] = send_time;
                            if (hop->sent_count == 0) {
                                hop->first_send_time = send_time;
                            }
                            hop->sent_count++;
                            sent_this_round++;
                            probes_since_event_check++;
                            
                            // 每发送3个探测，处理一次事件队列
                            if (probes_since_event_check >= 3) {
                                probes_since_event_check = 0;
                                mtr_tcp_event quick_event;
                                int event_processed = 0;
                                while (tcp_event_queue_try_pop(&event_queue, &quick_event) == 0 && event_processed < 10) {
                                    int quick_ttl = quick_event.ttl;
                                    if (quick_ttl >= 1 && quick_ttl <= max_ttl) {
                                        mtr_hop_state *quick_hop = &session.hops[quick_ttl];
                                        
                                        // 检查条件：probe_index 在有效范围内，且 send_times 已设置（说明该探测已发送）
                                        if (quick_event.probe_index >= 0 && quick_event.probe_index < times && 
                                            quick_hop->send_times[quick_event.probe_index] > 0) {
                                            if (quick_hop->rtts[quick_event.probe_index] == 0.0 && 
                                                quick_hop->src_ips[quick_event.probe_index][0] == '\0') {
                                                double quick_rtt = (double)(quick_event.recv_time - quick_hop->send_times[quick_event.probe_index]);
                                                if (quick_rtt > 0 && quick_rtt < 60000) {
                                                    quick_hop->rtts[quick_event.probe_index] = quick_rtt;
                                                    safe_strncpy(quick_hop->src_ips[quick_event.probe_index], 
                                                                quick_event.src_ip, 
                                                                sizeof(quick_hop->src_ips[quick_event.probe_index]));
                                                    quick_hop->recv_count++;
                                                }
                                            }
                                        }
                                        
                                        if (strcmp(quick_event.src_ip, target_ip) == 0 || quick_event.is_target_reply) {
                                            if (!session.target_reached) {
                                                session.target_reached = 1;
                                                session.target_reached_ttl = quick_ttl;
                                                if (quick_ttl == ttl) {
                                                    current_ttl_target_reached = 1;
                                                }
                                                quick_hop->ttl_done = 1;
                                                for (int t = quick_ttl + 1; t <= max_ttl; t++) {
                                                    session.hops[t].ttl_done = 1;
                                                }
                                                if (quick_ttl != ttl) {
                                                    break;
                                                }
                                            }
                                        }
                                    }
                                    event_processed++;
                                }
                                
                                if (session.target_reached && session.target_reached_ttl != ttl) {
                                    break;
                                }
                            }
                            
                            if (hop->sent_count < times) {
                                uint32_t gap_us = current_ttl_target_reached ? MTR_TARGET_PROBE_GAP_US : MTR_TCP_PROBE_GAP_US;
                                usleep(gap_us);
                            }
                        } else {
                            path->exceptionNum++;
                            // 尽可能把 errno 分类成可解释的错误码，供上层区分
                            int e = (send_errno != 0) ? send_errno : errno;
                            if (e != 0) {
                                const char *op = (failed_op && failed_op[0]) ? failed_op : "connect";
                                fatal_error_code = (int)mtr_classify_syscall_failure(op, e);
                                mtr_record_fatal_error(path, op, e);
                                if (fatal_error_code == cls_mtr_detector_error_permission_denied ||
                                    fatal_error_code == cls_mtr_detector_error_network_unreachable ||
                                    fatal_error_code == cls_mtr_detector_error_host_unreachable ||
                                    fatal_error_code == cls_mtr_detector_error_address_not_available ||
                                    fatal_error_code == cls_mtr_detector_error_address_in_use ||
                                    fatal_error_code == cls_mtr_detector_error_resource_exhausted ||
                                    fatal_error_code == cls_mtr_detector_error_connect_failed ||
                                    fatal_error_code == cls_mtr_detector_error_setsockopt_failed) {
                                    for (int t = ttl; t <= max_ttl; t++) {
                                        session.hops[t].ttl_done = 1;
                                    }
                                    consecutive_timeout_stopped = 1;
                                }
                            } else {
                                fatal_error_code = (int)cls_mtr_detector_error_connect_failed;
                            }
                            // 发送失败，关闭并释放槽位
                            pthread_mutex_lock(&worker_ctx.mutex);
                            if (tcp_sockets[slot] == tcp_sock) {
                                close(tcp_sock);
                                tcp_sockets[slot] = -1;
                            }
                            pthread_mutex_unlock(&worker_ctx.mutex);
                            hop->ttl_done = 1;
                            break;
                        }
                        
                        if (session.target_reached && session.target_reached_ttl != ttl) {
                            break;
                        }
                    }
                    
                    if (hop->sent_count >= times) {
                        if (mtr_check_consecutive_timeouts_and_stop(session.hops,
                                                                    max_ttl,
                                                                    times,
                                                                    timeout_ms,
                                                                    current_time,
                                                                    ttl,
                                                                    path,
                                                                    NULL)) {
                            consecutive_timeout_stopped = 1;
                            break;
                        }
                    }
                }
                
                if (session.target_reached || consecutive_timeout_stopped) {
                    break;
                }
            }
        }
        
        // 3. 检查完成状态（与 UDP 相同逻辑）
        if (session.target_reached) {
            int target_ttl = session.target_reached_ttl;
            mtr_hop_state *target_hop = &session.hops[target_ttl];
            
            uint64_t target_elapsed = current_time - target_hop->first_send_time;
            if (target_hop->sent_count >= times && (target_hop->recv_count >= times || target_elapsed > (uint64_t)timeout_ms)) {
                break;
            }
        } else {
            if (mtr_check_consecutive_timeouts_and_stop(session.hops,
                                                        max_ttl,
                                                        times,
                                                        timeout_ms,
                                                        current_time,
                                                        max_ttl,
                                                        path,
                                                        "probe_tcp_parallel")) {
                consecutive_timeout_stopped = 1;
            }
            
            // 如果连续超时导致停止，跳出循环
            if (consecutive_timeout_stopped) {
                break;
            }
            
            int all_done = 1;
            for (int ttl = 1; ttl <= max_ttl; ttl++) {
                mtr_hop_state *hop = &session.hops[ttl];
                if (!hop->ttl_done && (hop->sent_count < times || 
                    (current_time - hop->first_send_time) < (uint64_t)timeout_ms)) {
                    all_done = 0;
                    break;
                }
            }
            
            if (all_done) {
                break;
            }
        }
        
        usleep(MTR_MAIN_LOOP_SLEEP_US);
    }
    
    // 停止 worker 线程
    tcp_parallel_worker_stop(&worker_ctx);

    // 关闭所有残留的 in-flight TCP probe sockets（worker 已停止，不会再关闭它们）
    pthread_mutex_lock(&worker_ctx.mutex);
    for (int i = 0; i < tcp_socket_count; i++) {
        if (tcp_sockets[i] >= 0) {
            close(tcp_sockets[i]);
            tcp_sockets[i] = -1;
        }
    }
    pthread_mutex_unlock(&worker_ctx.mutex);
    
    // 汇总结果到 path->results（与 UDP 相同逻辑）
    int last_hop = 0;
    for (int ttl = 1; ttl <= max_ttl; ttl++) {
        mtr_hop_state *hop = &session.hops[ttl];
        
        if (ensure_path_results_capacity(path, (size_t)ttl) != 0) {
            break;
        }
        
        cls_mtr_hop_result *hop_result = &path->results[ttl - 1];
        fill_hop_result_from_state(hop_result, hop, ttl, times);
        if (hop->recv_count > 0) last_hop = ttl;
    }
    
    path->lastHop = last_hop;
    tcp_event_queue_destroy(&event_queue);
    int target_reached = session.target_reached;
    if (session.hops) {
        free(session.hops);
        session.hops = NULL;
    }
    
    if (!target_reached && (consecutive_timeout_stopped || deadline_hit)) {
        return (int)cls_mtr_detector_error_timeout;
    }
    
    return 0;
}


// 创建单个 socket（ICMP/UDP/TCP）
static socket_t create_socket(const char *protocol, int is_ipv6, unsigned int interface_index, int *out_bind_failed, int *out_errno) {
    socket_t sock = -1;
    int domain = is_ipv6 ? AF_INET6 : AF_INET;
    
    if (out_bind_failed) *out_bind_failed = 0;
    if (out_errno) *out_errno = 0;
    
    if (strcmp(protocol, "icmp") == 0) {
        sock = socket(domain, SOCK_DGRAM, is_ipv6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP);
    } else if (strcmp(protocol, "udp") == 0) {
        sock = socket(domain, SOCK_DGRAM, IPPROTO_UDP);
    } else if (strcmp(protocol, "tcp") == 0) {
        sock = socket(domain, SOCK_STREAM, IPPROTO_TCP);
    } else {
        return -1;
    }
    
    if (sock < 0) {
        if (out_errno) *out_errno = errno;
        return -1;
    }
    
    // 设置 socket 选项
    int reuse = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    
    // 设置非阻塞模式
    int flags = fcntl(sock, F_GETFL, 0);
    if (flags >= 0) {
        fcntl(sock, F_SETFL, flags | O_NONBLOCK);
    } 
    
    // 绑定到指定网络接口（如果提供了接口索引）
    if (interface_index > 0) {
        if (is_ipv6) {
#if defined(IPV6_BOUND_IF)
            if (setsockopt(sock, IPPROTO_IPV6, IPV6_BOUND_IF, &interface_index, sizeof(interface_index)) < 0) {
                if (out_bind_failed) *out_bind_failed = 1;
                if (out_errno) *out_errno = errno;
                close(sock);
                return -1;
            }
#else
            struct sockaddr_in6 addr6;
            memset(&addr6, 0, sizeof(addr6));
            addr6.sin6_family = AF_INET6;
            addr6.sin6_port = 0;
            addr6.sin6_scope_id = interface_index;
            if (bind(sock, (struct sockaddr *)&addr6, sizeof(addr6)) < 0) {
                if (out_bind_failed) *out_bind_failed = 1;
                if (out_errno) *out_errno = errno;
                close(sock);
                return -1;
            }
#endif
        } else {
#if defined(IP_BOUND_IF)
            if (setsockopt(sock, IPPROTO_IP, IP_BOUND_IF, &interface_index, sizeof(interface_index)) < 0) {
                if (out_bind_failed) *out_bind_failed = 1;
                if (out_errno) *out_errno = errno;
                close(sock);
                return -1;
            }
#else
            (void)interface_index;
#endif
        }
    }
    
    return sock;
}

// 根据目标地址解析本机源 IP（通过临时 UDP socket 连接获取）
static void resolve_local_ip_for_target(const char *resolved_ip, int is_ipv6, char *out_ip, size_t out_len) {
    if (!resolved_ip || !out_ip || out_len == 0) return;
    
    socket_t tmp_sock = socket(is_ipv6 ? AF_INET6 : AF_INET, SOCK_DGRAM, 0);
    if (tmp_sock < 0) {
        return;
    }
    
    int ret = -1;
    if (is_ipv6) {
        struct sockaddr_in6 addr6;
        memset(&addr6, 0, sizeof(addr6));
        addr6.sin6_family = AF_INET6;
        addr6.sin6_port = htons(33434);
        inet_pton(AF_INET6, resolved_ip, &addr6.sin6_addr);
        ret = connect(tmp_sock, (struct sockaddr *)&addr6, sizeof(addr6));
    } else {
        struct sockaddr_in addr4;
        memset(&addr4, 0, sizeof(addr4));
        addr4.sin_family = AF_INET;
        addr4.sin_port = htons(33434);
        inet_pton(AF_INET, resolved_ip, &addr4.sin_addr);
        ret = connect(tmp_sock, (struct sockaddr *)&addr4, sizeof(addr4));
    }
    
    if (ret == 0) {
        struct sockaddr_storage local_addr;
        socklen_t len = sizeof(local_addr);
        if (getsockname(tmp_sock, (struct sockaddr *)&local_addr, &len) == 0) {
            if (local_addr.ss_family == AF_INET6) {
                struct sockaddr_in6 *l6 = (struct sockaddr_in6 *)&local_addr;
                inet_ntop(AF_INET6, &l6->sin6_addr, out_ip, (socklen_t)out_len);
            } else if (local_addr.ss_family == AF_INET) {
                struct sockaddr_in *l4 = (struct sockaddr_in *)&local_addr;
                inet_ntop(AF_INET, &l4->sin_addr, out_ip, (socklen_t)out_len);
            }
        }
    }
    
    close(tmp_sock);
}

// 通过本机源 IP 反查出接口名（如 "en0"/"pdp_ip0"）
// 返回 0 表示找到；返回 -1 表示未找到/失败。
static int mtr_get_ifname_for_local_ip(const char *local_ip, int is_ipv6, char *out_ifname, size_t out_len) {
    if (!out_ifname || out_len == 0) return -1;
    out_ifname[0] = '\0';
    if (!local_ip || local_ip[0] == '\0') return -1;

    struct ifaddrs *ifaddrs_list = NULL;
    if (getifaddrs(&ifaddrs_list) != 0) {
        return -1;
    }

    int family = is_ipv6 ? AF_INET6 : AF_INET;

    struct in_addr target_v4;
    struct in6_addr target_v6;
    memset(&target_v4, 0, sizeof(target_v4));
    memset(&target_v6, 0, sizeof(target_v6));
    if (inet_pton(family, local_ip, is_ipv6 ? (void *)&target_v6 : (void *)&target_v4) != 1) {
        freeifaddrs(ifaddrs_list);
        return -1;
    }

    for (struct ifaddrs *ifa = ifaddrs_list; ifa != NULL; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || !ifa->ifa_name) continue;
        if (ifa->ifa_addr->sa_family != family) continue;

        // 仅考虑 UP/RUNNING 且非 loopback 的接口
        if ((ifa->ifa_flags & IFF_UP) == 0 || (ifa->ifa_flags & IFF_RUNNING) == 0 || (ifa->ifa_flags & IFF_LOOPBACK)) {
            continue;
        }

        if (!is_ipv6) {
            struct sockaddr_in *a4 = (struct sockaddr_in *)ifa->ifa_addr;
            if (memcmp(&a4->sin_addr, &target_v4, sizeof(struct in_addr)) == 0) {
                safe_strncpy(out_ifname, ifa->ifa_name, out_len);
                freeifaddrs(ifaddrs_list);
                return 0;
            }
        } else {
            struct sockaddr_in6 *a6 = (struct sockaddr_in6 *)ifa->ifa_addr;
            if (memcmp(&a6->sin6_addr, &target_v6, sizeof(struct in6_addr)) == 0) {
                safe_strncpy(out_ifname, ifa->ifa_name, out_len);
                freeifaddrs(ifaddrs_list);
                return 0;
            }
        }
    }

    freeifaddrs(ifaddrs_list);
    return -1;
}

// 当未显式指定 interface_index 时，选择一个“看起来最可能”的活动接口名（用于上报 interface_name）
// 优先级：en0（WiFi）> 任意 pdp_ip*（蜂窝）> en1（以太网/其他）> 任意 UP/RUNNING 非 loopback
static int mtr_pick_active_ifname(int is_ipv6, char *out_ifname, size_t out_len) {
    if (!out_ifname || out_len == 0) return -1;
    out_ifname[0] = '\0';

    struct ifaddrs *ifaddrs_list = NULL;
    if (getifaddrs(&ifaddrs_list) != 0) {
        return -1;
    }

    int family = is_ipv6 ? AF_INET6 : AF_INET;

    // 1) en0
    for (struct ifaddrs *ifa = ifaddrs_list; ifa != NULL; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || !ifa->ifa_name) continue;
        if (ifa->ifa_addr->sa_family != family) continue;
        if ((ifa->ifa_flags & IFF_UP) == 0 || (ifa->ifa_flags & IFF_RUNNING) == 0 || (ifa->ifa_flags & IFF_LOOPBACK)) continue;
        if (strcmp(ifa->ifa_name, "en0") == 0) {
            safe_strncpy(out_ifname, ifa->ifa_name, out_len);
            freeifaddrs(ifaddrs_list);
            return 0;
        }
    }

    // 2) 任意 pdp_ip*
    for (struct ifaddrs *ifa = ifaddrs_list; ifa != NULL; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || !ifa->ifa_name) continue;
        if (ifa->ifa_addr->sa_family != family) continue;
        if ((ifa->ifa_flags & IFF_UP) == 0 || (ifa->ifa_flags & IFF_RUNNING) == 0 || (ifa->ifa_flags & IFF_LOOPBACK)) continue;
        if (strncmp(ifa->ifa_name, "pdp_ip", 6) == 0) {
            safe_strncpy(out_ifname, ifa->ifa_name, out_len);
            freeifaddrs(ifaddrs_list);
            return 0;
        }
    }

    // 3) en1
    for (struct ifaddrs *ifa = ifaddrs_list; ifa != NULL; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || !ifa->ifa_name) continue;
        if (ifa->ifa_addr->sa_family != family) continue;
        if ((ifa->ifa_flags & IFF_UP) == 0 || (ifa->ifa_flags & IFF_RUNNING) == 0 || (ifa->ifa_flags & IFF_LOOPBACK)) continue;
        if (strcmp(ifa->ifa_name, "en1") == 0) {
            safe_strncpy(out_ifname, ifa->ifa_name, out_len);
            freeifaddrs(ifaddrs_list);
            return 0;
        }
    }

    // 4) 任意 UP/RUNNING 非 loopback
    for (struct ifaddrs *ifa = ifaddrs_list; ifa != NULL; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || !ifa->ifa_name) continue;
        if (ifa->ifa_addr->sa_family != family) continue;
        if ((ifa->ifa_flags & IFF_UP) == 0 || (ifa->ifa_flags & IFF_RUNNING) == 0 || (ifa->ifa_flags & IFF_LOOPBACK)) continue;
        safe_strncpy(out_ifname, ifa->ifa_name, out_len);
        freeifaddrs(ifaddrs_list);
        return 0;
    }

    freeifaddrs(ifaddrs_list);
    return -1;
}

// 执行 MTR 探测的核心逻辑
cls_mtr_detector_error_code cls_mtr_detector_perform_mtr(const char *target,
                                                         const cls_mtr_detector_config * _Nullable config,
                                                         cls_mtr_detector_result *result) {
    if (!result) return cls_mtr_detector_error_invalid_param;
    if (!target || target[0] == '\0') return cls_mtr_detector_error_invalid_target;
    
    // 先初始化输出（确保错误路径也可安全 free）
    memset(result, 0, sizeof(cls_mtr_detector_result));
    safe_strncpy(result->target, target, sizeof(result->target));
    safe_strncpy(result->method, "mtr", sizeof(result->method));
    
    // 解析配置
    const char *protocol = (config && config->protocol) ? config->protocol : "icmp";
    int max_ttl = (config && config->max_ttl > 0) ? config->max_ttl : MTR_DEFAULT_MAX_TTL;
    int timeout_ms = (config && config->timeout_ms > 0) ? config->timeout_ms : MTR_DEFAULT_TIMEOUT_MS;
    int times = (config && config->times > 0) ? config->times : MTR_DEFAULT_TIMES;
    unsigned int interface_index = (config) ? config->interface_index : 0;
    int prefer = (config) ? config->prefer : 0;
    
    
    // 限制参数范围
    if (max_ttl < 1) max_ttl = 1;
    if (max_ttl > 255) max_ttl = 255;
    if (timeout_ms < 100) timeout_ms = 100;
    if (timeout_ms > 60000) timeout_ms = 60000;
    if (times < 1) times = 1;
    if (times > 30) times = 30;
    
    // 解析目标地址
    char resolved_ip[INET6_ADDRSTRLEN];
    if (resolve_hostname(target, prefer, resolved_ip) != 0) {
        result->error_code = cls_mtr_detector_error_resolve_error;
        safe_strncpy(result->error_message, "Failed to resolve hostname", sizeof(result->error_message));
        return cls_mtr_detector_error_resolve_error;
    }
    
    int is_ipv6 = (strchr(resolved_ip, ':') != NULL);
    char device_ip[INET6_ADDRSTRLEN] = {0};
    resolve_local_ip_for_target(resolved_ip, is_ipv6, device_ip, sizeof(device_ip));
    
    cls_mtr_detector_error_code final_code = cls_mtr_detector_error_success;
    
    // 初始化结果内容
    result->max_paths = 1;
    result->paths_capacity = 1;
    result->paths = calloc(1, sizeof(cls_mtr_path_result));
    if (!result->paths) {
        final_code = cls_mtr_detector_error_unknown_error;
        result->error_code = final_code;
        safe_strncpy(result->error_message, "Failed to allocate result paths", sizeof(result->error_message));
        return final_code;
    }
    result->paths_count = 1;
    
    cls_mtr_path_result *path = &result->paths[0];
    // host 用域名，host_ip 用解析后的 IP
    init_path_result(path, target, protocol, resolved_ip);
    
    // 填充 interface_name
    // - 若显式指定 interface_index：用 if_indextoname 转换
    // - 若未指定（interface_index==0）：优先用“源 IP -> ifaddrs”反查，失败则按活动接口优先级兜底
    {
        char ifname[IF_NAMESIZE] = {0};
        if (interface_index > 0) {
            if (if_indextoname(interface_index, ifname) == NULL || ifname[0] == '\0') {
                // 兜底：索引无效或无法转换时仍输出索引，方便排查
                snprintf(path->interface_name, sizeof(path->interface_name), "ifindex:%u", interface_index);
            }
        } else {
            // 默认网卡：尽量给出真实接口名（en0/pdp_ip0/...），便于上层判断 WiFi/蜂窝
            if (device_ip[0] != '\0') {
                (void)mtr_get_ifname_for_local_ip(device_ip, is_ipv6, ifname, sizeof(ifname));
            }
            if (ifname[0] == '\0') {
                (void)mtr_pick_active_ifname(is_ipv6, ifname, sizeof(ifname));
            }
        }

        if (ifname[0] != '\0') {
            safe_strncpy(path->interface_name, ifname, sizeof(path->interface_name));
        }
    }
    
    // 创建 socket
    socket_t icmp_socket = -1;
    socket_t udp_socket = -1;
    socket_t *tcp_sockets = NULL;
    size_t tcp_socket_count = 0;
    
    if (strcmp(protocol, "icmp") == 0) {
        int bind_failed = 0;
        int sock_errno = 0;
        icmp_socket = create_socket("icmp", is_ipv6, interface_index, &bind_failed, &sock_errno);
        if (icmp_socket < 0) {
            if (bind_failed) {
                final_code = cls_mtr_detector_error_net_binding_failed;
            } else if (sock_errno == EPERM || sock_errno == EACCES) {
                final_code = cls_mtr_detector_error_permission_denied;
            } else {
                final_code = cls_mtr_detector_error_socket_create_error;
            }
            result->error_code = final_code;
            snprintf(result->error_message, sizeof(result->error_message),
                     "%s (errno=%d:%s)",
                     bind_failed ? "Failed to bind ICMP socket to interface" : "Failed to create ICMP socket",
                     sock_errno, (sock_errno > 0 ? strerror(sock_errno) : "unknown"));
            if (bind_failed) path->bindFailed++;
            goto cleanup;
        }
    } else if (strcmp(protocol, "udp") == 0) {
        int bind_failed = 0;
        int sock_errno = 0;
        udp_socket = create_socket("udp", is_ipv6, interface_index, &bind_failed, &sock_errno);
        if (udp_socket < 0) {
            if (bind_failed) {
                final_code = cls_mtr_detector_error_net_binding_failed;
            } else if (sock_errno == EPERM || sock_errno == EACCES) {
                final_code = cls_mtr_detector_error_permission_denied;
            } else {
                final_code = cls_mtr_detector_error_socket_create_error;
            }
            result->error_code = final_code;
            snprintf(result->error_message, sizeof(result->error_message),
                     "%s (errno=%d:%s)",
                     bind_failed ? "Failed to bind UDP socket to interface" : "Failed to create UDP socket",
                     sock_errno, (sock_errno > 0 ? strerror(sock_errno) : "unknown"));
            if (bind_failed) path->bindFailed++;
            goto cleanup;
        }
        // 额外创建 ICMP socket 用于接收 ICMP 错误/Time Exceeded
        bind_failed = 0;
        sock_errno = 0;
        icmp_socket = create_socket("icmp", is_ipv6, interface_index, &bind_failed, &sock_errno);
        if (icmp_socket < 0) {
            if (bind_failed) {
                final_code = cls_mtr_detector_error_net_binding_failed;
            } else if (sock_errno == EPERM || sock_errno == EACCES) {
                final_code = cls_mtr_detector_error_permission_denied;
            } else {
                final_code = cls_mtr_detector_error_socket_create_error;
            }
            result->error_code = final_code;
            snprintf(result->error_message, sizeof(result->error_message),
                     "%s (errno=%d:%s)",
                     bind_failed ? "Failed to bind ICMP recv socket for UDP to interface" : "Failed to create ICMP recv socket for UDP",
                     sock_errno, (sock_errno > 0 ? strerror(sock_errno) : "unknown"));
            if (bind_failed) path->bindFailed++;
            goto cleanup;
        }
    } else if (strcmp(protocol, "tcp") == 0) {
        int socket_count = max_ttl;
        if (socket_count < 10) socket_count = 10;
        if (socket_count > 30) socket_count = 30;
        
        tcp_sockets = malloc(sizeof(socket_t) * socket_count);
        if (!tcp_sockets) {
            final_code = cls_mtr_detector_error_socket_create_error;
            result->error_code = final_code;
            safe_strncpy(result->error_message, "Failed to allocate TCP socket array", sizeof(result->error_message));
            goto cleanup;
        }
        
        // TCP 并行探测采用“每个 probe 新建 socket 并绑定源端口编码 TTL/probe_index”的策略；
        // 这里的数组作为并发槽位，初始化为 -1，具体 socket 在 probe_tcp_parallel 内按需创建/释放。
        for (int i = 0; i < socket_count; i++) {
            tcp_sockets[i] = -1;
        }
        tcp_socket_count = socket_count;
        
        // 额外创建 ICMP socket 用于接收 ICMP 错误消息（Time Exceeded、Destination Unreachable 等）
        int bind_failed = 0;
        int sock_errno = 0;
        icmp_socket = create_socket("icmp", is_ipv6, interface_index, &bind_failed, &sock_errno);
        if (icmp_socket < 0) {
            if (bind_failed) {
                final_code = cls_mtr_detector_error_net_binding_failed;
            } else if (sock_errno == EPERM || sock_errno == EACCES) {
                final_code = cls_mtr_detector_error_permission_denied;
            } else {
                final_code = cls_mtr_detector_error_socket_create_error;
            }
            result->error_code = final_code;
            snprintf(result->error_message, sizeof(result->error_message),
                     "%s (errno=%d:%s)",
                     bind_failed ? "Failed to bind ICMP recv socket for TCP to interface" : "Failed to create ICMP recv socket for TCP",
                     sock_errno, (sock_errno > 0 ? strerror(sock_errno) : "unknown"));
            if (bind_failed) path->bindFailed++;
            goto cleanup;
        }
    } else {
        final_code = cls_mtr_detector_error_invalid_param;
        result->error_code = final_code;
        safe_strncpy(result->error_message, "Unsupported protocol, only icmp/udp/tcp are supported", sizeof(result->error_message));
        goto cleanup;
    }
    
    // 使用 Network.framework 监控网络状态（可选，用于网络状态检查）
    // 注意：实际的包发送和接收使用 socket，Network.framework 仅用于监控
    
    // 执行探测
    int last_hop = 0;
    
    if (strcmp(protocol, "icmp") == 0) {
        // ICMP 使用并行探测
        int probe_result = probe_icmp_parallel(resolved_ip, max_ttl, times, timeout_ms, is_ipv6, icmp_socket, path);
        if (probe_result == 0) {
            last_hop = path->lastHop;
            if (last_hop <= 0) {
                // 没有任何 hop 响应：按超时返回（更明确）
                final_code = (path->exceptionNum > 0) ? cls_mtr_detector_error_socket_create_error : cls_mtr_detector_error_timeout;
                result->error_code = final_code;
                safe_strncpy(result->error_message,
                             (path->exceptionNum > 0) ? "Probe failed: socket/send error" : "Probe timeout: no hop responded",
                             sizeof(result->error_message));
            }
        } else if (probe_result == (int)cls_mtr_detector_error_timeout) {
            // 未到达目标（可能是连续超时提前停止/全局 deadline 到期等）
            last_hop = path->lastHop;
            final_code = cls_mtr_detector_error_timeout;
            result->error_code = final_code;
            safe_strncpy(result->error_message, "Probe timeout: target host not reached", sizeof(result->error_message));
        } else if (probe_result < 0) {
            last_hop = path->lastHop;
            final_code = (cls_mtr_detector_error_code)probe_result;
            result->error_code = final_code;
            if (path->last_errno != 0 && path->last_error_op[0] != '\0') {
                snprintf(result->error_message, sizeof(result->error_message),
                         "Probe failed: %s (code=%ld, op=%s, errno=%d:%s)",
                         mtr_error_name(final_code), (long)final_code,
                         path->last_error_op, path->last_errno, strerror(path->last_errno));
            } else {
                snprintf(result->error_message, sizeof(result->error_message),
                         "Probe failed: %s (code=%ld)",
                         mtr_error_name(final_code), (long)final_code);
            }
        } else {
            final_code = (path->exceptionNum > 0) ? cls_mtr_detector_error_socket_create_error : cls_mtr_detector_error_unknown_error;
            result->error_code = final_code;
            safe_strncpy(result->error_message,
                         (path->exceptionNum > 0) ? "Probe failed: socket/send error" : "Probe failed: unknown error",
                         sizeof(result->error_message));
        }
    } else if (strcmp(protocol, "udp") == 0) {
        // UDP 使用并行探测
        int probe_result = probe_udp_parallel(resolved_ip, max_ttl, times, timeout_ms, is_ipv6, udp_socket, icmp_socket, path);
        if (probe_result == 0) {
            last_hop = path->lastHop;
            if (last_hop <= 0) {
                final_code = (path->exceptionNum > 0) ? cls_mtr_detector_error_socket_create_error : cls_mtr_detector_error_timeout;
                result->error_code = final_code;
                safe_strncpy(result->error_message,
                             (path->exceptionNum > 0) ? "Probe failed: socket/send error" : "Probe timeout: no hop responded",
                             sizeof(result->error_message));
            }
        } else if (probe_result == (int)cls_mtr_detector_error_timeout) {
            // 未到达目标（可能是连续超时提前停止/全局 deadline 到期等）
            last_hop = path->lastHop;
            final_code = cls_mtr_detector_error_timeout;
            result->error_code = final_code;
            safe_strncpy(result->error_message, "Probe timeout: target host not reached", sizeof(result->error_message));
        } else if (probe_result < 0) {
            last_hop = path->lastHop;
            final_code = (cls_mtr_detector_error_code)probe_result;
            result->error_code = final_code;
            if (path->last_errno != 0 && path->last_error_op[0] != '\0') {
                snprintf(result->error_message, sizeof(result->error_message),
                         "Probe failed: %s (code=%ld, op=%s, errno=%d:%s)",
                         mtr_error_name(final_code), (long)final_code,
                         path->last_error_op, path->last_errno, strerror(path->last_errno));
            } else {
                snprintf(result->error_message, sizeof(result->error_message),
                         "Probe failed: %s (code=%ld)",
                         mtr_error_name(final_code), (long)final_code);
            }
        } else {
            final_code = (path->exceptionNum > 0) ? cls_mtr_detector_error_socket_create_error : cls_mtr_detector_error_unknown_error;
            result->error_code = final_code;
            safe_strncpy(result->error_message,
                         (path->exceptionNum > 0) ? "Probe failed: socket/send error" : "Probe failed: unknown error",
                         sizeof(result->error_message));
        }
    } else if (strcmp(protocol, "tcp") == 0) {
        // TCP 使用并行探测
        int probe_result = probe_tcp_parallel(resolved_ip, max_ttl, times, timeout_ms, is_ipv6, tcp_sockets, (int)tcp_socket_count, icmp_socket, interface_index, path);
        if (probe_result == 0) {
            last_hop = path->lastHop;
            if (last_hop <= 0) {
                final_code = (path->bindFailed > 0) ? cls_mtr_detector_error_net_binding_failed
                                                    : ((path->exceptionNum > 0) ? cls_mtr_detector_error_socket_create_error
                                                                                : cls_mtr_detector_error_timeout);
                result->error_code = final_code;
                safe_strncpy(result->error_message,
                             (path->exceptionNum > 0 || path->bindFailed > 0) ? "Probe failed: socket/bind/send error" : "Probe timeout: no hop responded",
                             sizeof(result->error_message));
            }
        } else if (probe_result == (int)cls_mtr_detector_error_timeout) {
            // 未到达目标（可能是连续超时提前停止/全局 deadline 到期等）
            last_hop = path->lastHop;
            final_code = cls_mtr_detector_error_timeout;
            result->error_code = final_code;
            safe_strncpy(result->error_message, "Probe timeout: target host not reached", sizeof(result->error_message));
        } else if (probe_result < 0) {
            last_hop = path->lastHop;
            final_code = (cls_mtr_detector_error_code)probe_result;
            result->error_code = final_code;
            if (path->last_errno != 0 && path->last_error_op[0] != '\0') {
                snprintf(result->error_message, sizeof(result->error_message),
                         "Probe failed: %s (code=%ld, op=%s, errno=%d:%s)",
                         mtr_error_name(final_code), (long)final_code,
                         path->last_error_op, path->last_errno, strerror(path->last_errno));
            } else {
                snprintf(result->error_message, sizeof(result->error_message),
                         "Probe failed: %s (code=%ld)",
                         mtr_error_name(final_code), (long)final_code);
            }

        } else {
            final_code = (path->bindFailed > 0) ? cls_mtr_detector_error_net_binding_failed
                                                : ((path->exceptionNum > 0) ? cls_mtr_detector_error_socket_create_error
                                                                            : cls_mtr_detector_error_unknown_error);
            result->error_code = final_code;
            safe_strncpy(result->error_message,
                         (path->exceptionNum > 0 || path->bindFailed > 0) ? "Probe failed: socket/bind/send error" : "Probe failed: unknown error",
                         sizeof(result->error_message));
        }
    }
    
    // 构造 path 字符串：timestamp:interface/protocol 源IP-目标IP
    const char *source_ip_for_path = (device_ip[0] != '\0') ? device_ip : "*";
    const char *dest_ip_for_path = path->host_ip[0] ? path->host_ip : path->host;
    snprintf(path->path, sizeof(path->path), "%lld : %s-%s",
             path->timestamp, source_ip_for_path, dest_ip_for_path);
    
    
cleanup:
    // 清理 socket（无论成功/失败都需要）
    if (icmp_socket >= 0) {
        close(icmp_socket);
    }
    if (udp_socket >= 0) {
        close(udp_socket);
    }
    if (tcp_sockets) {
        for (size_t i = 0; i < tcp_socket_count; i++) {
            if (tcp_sockets[i] >= 0) close(tcp_sockets[i]);
        }
        free(tcp_sockets);
    }
    
    // 统一返回：不要覆盖失败码
    result->error_code = final_code;
    if (final_code == cls_mtr_detector_error_success) {
    } else {
    }
    return final_code;
}

// 将 MTR 结果转换为 JSON 格式
static int json_append(char *buf, size_t buf_size, size_t *used, const char *fmt, ...) {
    if (!buf || buf_size == 0 || !used || !fmt) return -1;
    if (*used >= buf_size) return -1;
    
    va_list args;
    va_start(args, fmt);
    int n = vsnprintf(buf + *used, buf_size - *used, fmt, args);
    va_end(args);
    
    if (n < 0) return -1;
    if ((size_t)n >= (buf_size - *used)) return -1;  // 被截断
    
    *used += (size_t)n;
    return 0;
}

static int json_append_escaped_string(char *buf, size_t buf_size, size_t *used, const char *s) {
    if (!s) s = "";
    if (json_append(buf, buf_size, used, "\"") != 0) return -1;
    
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        unsigned char c = *p;
        switch (c) {
            case '\"': if (json_append(buf, buf_size, used, "\\\"") != 0) return -1; break;
            case '\\': if (json_append(buf, buf_size, used, "\\\\") != 0) return -1; break;
            case '\b': if (json_append(buf, buf_size, used, "\\b") != 0) return -1; break;
            case '\f': if (json_append(buf, buf_size, used, "\\f") != 0) return -1; break;
            case '\n': if (json_append(buf, buf_size, used, "\\n") != 0) return -1; break;
            case '\r': if (json_append(buf, buf_size, used, "\\r") != 0) return -1; break;
            case '\t': if (json_append(buf, buf_size, used, "\\t") != 0) return -1; break;
            default:
                if (c < 0x20) {
                    if (json_append(buf, buf_size, used, "\\u%04x", (unsigned int)c) != 0) return -1;
                } else {
                    if (json_append(buf, buf_size, used, "%c", (char)c) != 0) return -1;
                }
                break;
        }
    }
    
    if (json_append(buf, buf_size, used, "\"") != 0) return -1;
    return 0;
}

int cls_mtr_detector_result_to_json(const cls_mtr_detector_result *result,
                                    cls_mtr_detector_error_code error_code,
                                    char *json_buffer,
                                    size_t buffer_size) {
    if (!result || !json_buffer || buffer_size == 0) return -1;
    
    size_t used = 0;
    if (json_append(json_buffer, buffer_size, &used, "{") != 0) return -1;
    
    // net.origin 层（单层键）
    if (json_append(json_buffer, buffer_size, &used, "\"net.origin\":{") != 0) return -1;
    
    if (json_append(json_buffer, buffer_size, &used, "\"method\":") != 0) return -1;
    if (json_append_escaped_string(json_buffer, buffer_size, &used, result->method) != 0) return -1;
    if (json_append(json_buffer, buffer_size, &used, ",\"host\":") != 0) return -1;
    if (json_append_escaped_string(json_buffer, buffer_size, &used, result->target) != 0) return -1;
    
    // 首层 type 使用探测协议类型
    const char *top_type = (result->paths_count > 0 && result->paths && result->paths[0].protocol[0])
                               ? result->paths[0].protocol
                               : "mtr";
    if (json_append(json_buffer, buffer_size, &used, ",\"type\":") != 0) return -1;
    if (json_append_escaped_string(json_buffer, buffer_size, &used, top_type) != 0) return -1;
    
    if (json_append(json_buffer, buffer_size, &used, ",\"max_paths\":%d", result->max_paths > 0 ? result->max_paths : 1) != 0) return -1;
    
    // paths 数组
    if (json_append(json_buffer, buffer_size, &used, ",\"paths\":[") != 0) return -1;
    
    const size_t paths_count = (result->paths && result->paths_count > 0) ? result->paths_count : 0;
    for (size_t i = 0; i < paths_count; i++) {
        const cls_mtr_path_result *path = &result->paths[i];
        if (i > 0) {
            if (json_append(json_buffer, buffer_size, &used, ",") != 0) return -1;
        }
        if (json_append(json_buffer, buffer_size, &used, "{") != 0) return -1;
        
        if (json_append(json_buffer, buffer_size, &used, "\"method\":") != 0) return -1;
        if (json_append_escaped_string(json_buffer, buffer_size, &used, path->method) != 0) return -1;
        
        if (json_append(json_buffer, buffer_size, &used, ",\"host\":") != 0) return -1;
        if (json_append_escaped_string(json_buffer, buffer_size, &used, path->host) != 0) return -1;
        
        if (json_append(json_buffer, buffer_size, &used, ",\"host_ip\":") != 0) return -1;
        if (json_append_escaped_string(json_buffer, buffer_size, &used, path->host_ip[0] ? path->host_ip : "") != 0) return -1;
        
        if (json_append(json_buffer, buffer_size, &used, ",\"type\":\"path\"") != 0) return -1;
        
        // 直接使用已构造的 path（timestamp:源IP-目标IP）
        if (json_append(json_buffer, buffer_size, &used, ",\"path\":") != 0) return -1;
        if (json_append_escaped_string(json_buffer, buffer_size, &used, path->path) != 0) return -1;
        
        if (json_append(json_buffer, buffer_size, &used, ",\"lastHop\":%d", path->lastHop) != 0) return -1;
        if (json_append(json_buffer, buffer_size, &used, ",\"timestamp\":%lld", path->timestamp) != 0) return -1;
        
        // interface_name：紧跟 timestamp / protocol 输出，方便上层直接消费
        if (json_append(json_buffer, buffer_size, &used, ",\"interface_name\":") != 0) return -1;
        if (json_append_escaped_string(json_buffer, buffer_size, &used, path->interface_name[0] ? path->interface_name : "") != 0) return -1;
        
        if (json_append(json_buffer, buffer_size, &used, ",\"protocol\":") != 0) return -1;
        if (json_append_escaped_string(json_buffer, buffer_size, &used, path->protocol) != 0) return -1;
        
        if (json_append(json_buffer, buffer_size, &used, ",\"exceptionNum\":%d", path->exceptionNum) != 0) return -1;
        if (json_append(json_buffer, buffer_size, &used, ",\"bindFailed\":%d", path->bindFailed) != 0) return -1;
        
        // result 数组
        if (json_append(json_buffer, buffer_size, &used, ",\"result\":[") != 0) return -1;
        
        // 如果整条路径都没有任何回包，为了避免输出一堆 "* hop"，只输出 1 条空 hop
        int path_has_any_reply = 0;
        if (path->results && path->results_count > 0) {
            for (size_t j = 0; j < path->results_count; j++) {
                const cls_mtr_hop_result *h = &path->results[j];
                if (h->responseNum > 0) { path_has_any_reply = 1; break; }
                if (h->ip[0] != '\0' && strcmp(h->ip, "*") != 0) { path_has_any_reply = 1; break; }
            }
        }

        size_t output_count = 0;
        if (path_has_any_reply && path->results && path->results_count > 0) {
            output_count = (path->lastHop > 0) ? (size_t)path->lastHop : path->results_count;
            if (output_count > path->results_count) output_count = path->results_count;
        }

        if (!path_has_any_reply) {
            // 仅输出一条空 hop
            if (json_append(json_buffer, buffer_size, &used, "{") != 0) return -1;
            if (json_append(json_buffer, buffer_size, &used, "\"loss\":%.2f", 1.0) != 0) return -1;
            if (json_append(json_buffer, buffer_size, &used, ",\"latency_min\":%.3f", 0.0) != 0) return -1;
            if (json_append(json_buffer, buffer_size, &used, ",\"latency_max\":%.3f", 0.0) != 0) return -1;
            if (json_append(json_buffer, buffer_size, &used, ",\"latency\":%.3f", 0.0) != 0) return -1;
            if (json_append(json_buffer, buffer_size, &used, ",\"responseNum\":%d", 0) != 0) return -1;
            if (json_append(json_buffer, buffer_size, &used, ",\"ip\":") != 0) return -1;
            if (json_append_escaped_string(json_buffer, buffer_size, &used, "*") != 0) return -1;
            if (json_append(json_buffer, buffer_size, &used, ",\"hop\":%d", 1) != 0) return -1;
            if (json_append(json_buffer, buffer_size, &used, ",\"stddev\":%.3f", 0.0) != 0) return -1;
            if (json_append(json_buffer, buffer_size, &used, "}") != 0) return -1;
        } else {
            for (size_t j = 0; j < output_count; j++) {
                const cls_mtr_hop_result *hop = &path->results[j];
                if (j > 0) {
                    if (json_append(json_buffer, buffer_size, &used, ",") != 0) return -1;
                }
                if (json_append(json_buffer, buffer_size, &used, "{") != 0) return -1;
                
                if (json_append(json_buffer, buffer_size, &used, "\"loss\":%.2f", hop->loss) != 0) return -1;
                if (json_append(json_buffer, buffer_size, &used, ",\"latency_min\":%.3f", hop->latency_min) != 0) return -1;
                if (json_append(json_buffer, buffer_size, &used, ",\"latency_max\":%.3f", hop->latency_max) != 0) return -1;
                if (json_append(json_buffer, buffer_size, &used, ",\"latency\":%.3f", hop->latency) != 0) return -1;
                if (json_append(json_buffer, buffer_size, &used, ",\"responseNum\":%d", hop->responseNum) != 0) return -1;
                
                if (json_append(json_buffer, buffer_size, &used, ",\"ip\":") != 0) return -1;
                if (json_append_escaped_string(json_buffer, buffer_size, &used, hop->ip[0] ? hop->ip : "*") != 0) return -1;
                
                if (json_append(json_buffer, buffer_size, &used, ",\"hop\":%d", hop->hop) != 0) return -1;
                if (json_append(json_buffer, buffer_size, &used, ",\"stddev\":%.3f", hop->stddev) != 0) return -1;
                
                if (json_append(json_buffer, buffer_size, &used, "}") != 0) return -1;
            }
        }
        
        if (json_append(json_buffer, buffer_size, &used, "]") != 0) return -1;  // end result
        if (json_append(json_buffer, buffer_size, &used, "}") != 0) return -1;  // end path obj
    }
    
    if (json_append(json_buffer, buffer_size, &used, "]") != 0) return -1; // end paths
    if (json_append(json_buffer, buffer_size, &used, "}") != 0) return -1;  // end net.origin
    
    // 可选错误信息
    if (error_code != cls_mtr_detector_error_success || (result->error_message[0] != '\0')) {
        if (json_append(json_buffer, buffer_size, &used, ",\"errCode\":%ld", (long)error_code) != 0) return -1;
        if (result->error_message[0] != '\0') {
            if (json_append(json_buffer, buffer_size, &used, ",\"errMsg\":") != 0) return -1;
            if (json_append_escaped_string(json_buffer, buffer_size, &used, result->error_message) != 0) return -1;
        }
    }
    
    if (json_append(json_buffer, buffer_size, &used, "}") != 0) return -1; // end root
    return (int)used;
}

// 释放 MTR 探测结果内存
void cls_mtr_detector_free_result(cls_mtr_detector_result *result) {
    if (!result) return;
    
    if (result->paths) {
        for (size_t i = 0; i < result->paths_count; i++) {
            if (result->paths[i].results) {
                free(result->paths[i].results);
                result->paths[i].results = NULL;
            }
        }
        free(result->paths);
        result->paths = NULL;
    }
    
    memset(result, 0, sizeof(cls_mtr_detector_result));
}

