//
//  cls_mtr_detector.m
//  network_ios
//
//  MTR 网络路径探测器 - 使用 Network.framework
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

// 日志宏定义
#define MTR_LOG_DEBUG(fmt, ...) \
    NSLog(@"[MTR DEBUG] " fmt, ##__VA_ARGS__)
#define MTR_LOG_INFO(fmt, ...) \
    NSLog(@"[MTR INFO] " fmt, ##__VA_ARGS__)
#define MTR_LOG_ERROR(fmt, ...) \
    NSLog(@"[MTR ERROR] " fmt, ##__VA_ARGS__)

// 常量定义
#define MTR_DEFAULT_MAX_TTL 30
#define MTR_DEFAULT_TIMEOUT_MS 2000
#define MTR_DEFAULT_TIMES 3
#define MTR_SRC_PORT_BASE 33434
#define MTR_DST_PORT_BASE 33434
#define MTR_TCP_DST_PORT 80
#define MTR_RECV_BUFFER_SIZE 4096
#define MAX_CONSECUTIVE_TIMEOUTS 5

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

// 辅助函数：安全字符串复制
static int safe_strncpy(char *dest, const char *src, size_t dest_size) {
    if (!dest || !src || dest_size == 0) return -1;
    strncpy(dest, src, dest_size - 1);
    dest[dest_size - 1] = '\0';
    return 0;
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
    hop->loss = 100.0;
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

// 发送 ICMP Echo 请求
static int send_icmp_echo(socket_t icmp_socket, const char *target_ip, int ttl, 
                          int sequence, uint16_t icmp_identifier, uint64_t *send_time) {
    if (!target_ip || icmp_socket < 0 || ttl < 1 || ttl > 255) return -1;
    
    int is_ipv6 = (strchr(target_ip, ':') != NULL);
    
    // 设置 TTL
    int ttl_value = ttl;
    if (is_ipv6) {
        if (setsockopt(icmp_socket, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &ttl_value, sizeof(ttl_value)) < 0) {
            MTR_LOG_ERROR("send_icmp_echo: failed to set IPV6_UNICAST_HOPS=%d: %s", ttl, strerror(errno));
            return -1;
        }
        MTR_LOG_DEBUG("send_icmp_echo: set IPV6_UNICAST_HOPS=%d for target=%s", ttl, target_ip);
    } else {
        if (setsockopt(icmp_socket, IPPROTO_IP, IP_TTL, &ttl_value, sizeof(ttl_value)) < 0) {
            MTR_LOG_ERROR("send_icmp_echo: failed to set IP_TTL=%d: %s", ttl, strerror(errno));
            return -1;
        }
        MTR_LOG_DEBUG("send_icmp_echo: set IP_TTL=%d for target=%s", ttl, target_ip);
    }
    
    // 构建 ICMP 包
    // 注意：在 iOS/macOS 上使用 SOCK_DGRAM 时，内核会自动管理 ICMP ID
    // 应用程序设置的 ID 可能被内核改写，所以这里设置的值可能不会生效
    // 但为了兼容性，仍然设置 ID（内核可能会使用它，也可能不使用）
    struct IcmpPacket icmp_packet;
    memset(&icmp_packet, 0, sizeof(icmp_packet));
    icmp_packet.type = is_ipv6 ? 128 : 8; // ICMP6_ECHO_REQUEST : ICMP_ECHO
    icmp_packet.code = 0;
    icmp_packet.id = icmp_identifier;  // 可能被内核改写
    icmp_packet.sequence = htons((uint16_t)ttl);  // 序列号 = TTL，用于匹配响应
    icmp_packet.timestamp = get_current_timestamp_ms();
    snprintf(icmp_packet.data, sizeof(icmp_packet.data), "MTR-%d-%d", ttl, sequence);
    
    MTR_LOG_DEBUG("send_icmp_echo: sending ICMP%s Echo Request to %s, TTL=%d, seq=%d, id=%u (may be rewritten by kernel)",
                  is_ipv6 ? "v6" : "v4", target_ip, ttl, sequence, icmp_identifier);
    
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
        if (inet_pton(AF_INET6, target_ip, &addr6.sin6_addr) != 1) return -1;
        sent = sendto(icmp_socket, &icmp_packet, sizeof(icmp_packet), 0, 
                     (struct sockaddr *)&addr6, sizeof(addr6));
    } else {
        struct sockaddr_in addr4;
        memset(&addr4, 0, sizeof(addr4));
        addr4.sin_family = AF_INET;
        if (inet_pton(AF_INET, target_ip, &addr4.sin_addr) != 1) return -1;
        sent = sendto(icmp_socket, &icmp_packet, sizeof(icmp_packet), 0, 
                     (struct sockaddr *)&addr4, sizeof(addr4));
    }
    
    if (sent < 0 || sent != (ssize_t)sizeof(icmp_packet)) {
        MTR_LOG_ERROR("send_icmp_echo: sendto failed: %s (sent=%zd, expected=%zu)", 
                      strerror(errno), sent, sizeof(icmp_packet));
        return -1;
    }
    
    if (send_time) {
        *send_time = get_current_timestamp_ms();
    }
    
    MTR_LOG_DEBUG("send_icmp_echo: successfully sent %zd bytes to %s, TTL=%d", 
                  sent, target_ip, ttl);
    
    return 0;
}

// ICMP 接收线程参数与入口
typedef struct {
    socket_t sock;
    int timeout_ms;
    const char *target_ip;
    int ttl;
    int is_ipv6;
    uint64_t send_time;
    uint16_t expected_id;
    double rtt_out;
    char src_ip_out[INET6_ADDRSTRLEN];
    int result;
} icmp_receive_params;

static void *icmp_receive_thread(void *arg) {
    icmp_receive_params *params = (icmp_receive_params *)arg;
    params->src_ip_out[0] = '\0';
    params->result = receive_icmp_response(params->sock,
                                           params->timeout_ms,
                                           params->target_ip,
                                           params->ttl,
                                           params->is_ipv6,
                                           &params->rtt_out,
                                           params->src_ip_out,
                                           params->send_time,
                                           params->expected_id);
    return NULL;
}

// 发送 UDP 包
static int send_udp_packet(socket_t udp_socket, const char *target_ip, int ttl, 
                           int sequence, uint16_t *src_port, uint64_t *send_time) {
    if (!target_ip || udp_socket < 0 || ttl < 1 || ttl > 255) return -1;
    
    int is_ipv6 = (strchr(target_ip, ':') != NULL);
    
    // 设置 TTL
    int ttl_value = ttl;
    if (is_ipv6) {
        if (setsockopt(udp_socket, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &ttl_value, sizeof(ttl_value)) < 0) {
            MTR_LOG_ERROR("send_udp_packet: failed to set IPV6_UNICAST_HOPS=%d: %s", ttl, strerror(errno));
            return -1;
        }
        MTR_LOG_DEBUG("send_udp_packet: set IPV6_UNICAST_HOPS=%d for target=%s", ttl, target_ip);
    } else {
        if (setsockopt(udp_socket, IPPROTO_IP, IP_TTL, &ttl_value, sizeof(ttl_value)) < 0) {
            MTR_LOG_ERROR("send_udp_packet: failed to set IP_TTL=%d: %s", ttl, strerror(errno));
            return -1;
        }
        MTR_LOG_DEBUG("send_udp_packet: set IP_TTL=%d for target=%s", ttl, target_ip);
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
    
    ssize_t sent = 0;
    if (is_ipv6) {
        struct sockaddr_in6 addr6;
        memset(&addr6, 0, sizeof(addr6));
        addr6.sin6_family = AF_INET6;
        if (inet_pton(AF_INET6, target_ip, &addr6.sin6_addr) != 1) return -1;
        addr6.sin6_port = htons(MTR_DST_PORT_BASE + ttl);
        sent = sendto(udp_socket, data, sizeof(data), 0, (struct sockaddr *)&addr6, sizeof(addr6));
    } else {
        struct sockaddr_in addr4;
        memset(&addr4, 0, sizeof(addr4));
        addr4.sin_family = AF_INET;
        if (inet_pton(AF_INET, target_ip, &addr4.sin_addr) != 1) return -1;
        addr4.sin_port = htons(MTR_DST_PORT_BASE + ttl);
        sent = sendto(udp_socket, data, sizeof(data), 0, (struct sockaddr *)&addr4, sizeof(addr4));
    }
    
    if (sent < 0 || sent != (ssize_t)sizeof(data)) {
        MTR_LOG_ERROR("send_udp_packet: sendto failed: %s (sent=%zd, expected=%zu), target=%s, dst_port=%u, ttl=%d",
                      strerror(errno), sent, sizeof(data), target_ip, MTR_DST_PORT_BASE + ttl, ttl);
        return -1;
    }
    
    if (send_time) {
        *send_time = get_current_timestamp_ms();
    }
    
    MTR_LOG_DEBUG("send_udp_packet: sent %zd bytes to %s, dst_port=%u, ttl=%d", 
                  sent, target_ip, MTR_DST_PORT_BASE + ttl, ttl);
    
    return 0;
}

// 发送 TCP SYN 包
static int send_tcp_syn(socket_t tcp_socket, const char *target_ip, int ttl, 
                        int sequence, uint16_t *src_port, uint64_t *send_time) {
    if (!target_ip || tcp_socket < 0 || ttl < 1 || ttl > 255) return -1;
    
    int is_ipv6 = (strchr(target_ip, ':') != NULL);
    
    // 设置 TTL
    int ttl_value = ttl;
    if (is_ipv6) {
        if (setsockopt(tcp_socket, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &ttl_value, sizeof(ttl_value)) < 0) {
            return -1;
        }
    } else {
        if (setsockopt(tcp_socket, IPPROTO_IP, IP_TTL, &ttl_value, sizeof(ttl_value)) < 0) {
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
            fcntl(tcp_socket, F_SETFL, flags);
            return -1;
        }
        addr4.sin_port = htons(MTR_TCP_DST_PORT);
        connect_result = connect(tcp_socket, (struct sockaddr *)&addr4, sizeof(addr4));
    }
    
    fcntl(tcp_socket, F_SETFL, flags);
    
    if (send_time) {
        *send_time = get_current_timestamp_ms();
    }
    
    // connect 失败是预期的（TTL 过期或端口关闭），我们通过错误队列接收 ICMP 错误
    usleep(20000); // 20ms，确保 SYN 包发送
    
    return 0;
}

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
            MTR_LOG_DEBUG("parse_icmp_response: detected IPv4 header (len=%zu), skipping to ICMP payload (len=%zu)", ip_hdr_len, icmp_len);
        }
    } else if (ip_version == 6 && buffer_len >= 40) {
        size_t ip6_hdr_len = 40; // 固定长度
        if (buffer_len >= ip6_hdr_len + sizeof(struct mtr_icmphdr)) {
            icmp_base = buffer + ip6_hdr_len;
            icmp_len = buffer_len - ip6_hdr_len;
            if (original_ttl) *original_ttl = buffer[7]; // IPv6 Hop Limit 在偏移7
            MTR_LOG_DEBUG("parse_icmp_response: detected IPv6 header (len=%zu), skipping to ICMP payload (len=%zu)", ip6_hdr_len, icmp_len);
        }
    }
    
    if (icmp_len < sizeof(struct mtr_icmphdr)) {
        MTR_LOG_DEBUG("parse_icmp_response: ICMP payload too small after skipping IP header: %zu bytes", icmp_len);
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
        MTR_LOG_DEBUG("parse_icmp_response: ICMP%s Echo Reply, type=%d, code=%d, id=%u, seq=%u",
                      is_ipv6 ? "v6" : "v4", icmp_hdr->type, icmp_hdr->code, id_value, seq_value);
        return 0;
    } else if (icmp_hdr->type == time_exceeded_type || icmp_hdr->type == dest_unreach_type) {
        // ICMP Time Exceeded 或 Destination Unreachable
        if (is_echo_reply) *is_echo_reply = 0;
        
        const char *icmp_type_name = (icmp_hdr->type == time_exceeded_type) ? "Time Exceeded" : "Destination Unreachable";
        MTR_LOG_DEBUG("parse_icmp_response: ICMP%s %s, type=%d, code=%d",
                      is_ipv6 ? "v6" : "v4", icmp_type_name, icmp_hdr->type, icmp_hdr->code);
        
        // 解析原始 IP 头和数据
        if (icmp_len < 8 + 1) {
            MTR_LOG_DEBUG("parse_icmp_response: buffer too short for IP header, len=%zu", icmp_len);
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
                    MTR_LOG_DEBUG("parse_icmp_response: extracted from original UDP packet, dst_port=%u, extracted_ttl=%d",
                                  dst_port, extracted_ttl);
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
    
    MTR_LOG_DEBUG("parse_icmp_response: failed to parse ICMP response, type=%d, code=%d, buffer_len=%zu",
                  icmp_hdr->type, icmp_hdr->code, icmp_len);
    return -1;
}

// 接收 ICMP 响应（完整实现）
static int receive_icmp_response(socket_t sock, int timeout_ms, const char *target_ip, 
                                 int ttl, int is_ipv6, double *rtt_out, char *src_ip_out,
                                 uint64_t send_time, uint16_t expected_id) {
    if (sock < 0 || !target_ip || !rtt_out) return -1;
    
    MTR_LOG_DEBUG("receive_icmp_response: waiting for ICMP response, target=%s, TTL=%d, timeout=%dms", 
                  target_ip, ttl, timeout_ms);
    
    // 设置 socket 为非阻塞模式以便使用 select
    int flags = fcntl(sock, F_GETFL, 0);
    fcntl(sock, F_SETFL, flags | O_NONBLOCK);
    
    uint64_t start_time = get_current_timestamp_ms();
    uint16_t expected_id_host = (expected_id != 0) ? ntohs(expected_id) : 0;
    
    // 循环接收，直到超时或收到匹配的响应
    while (1) {
        // 检查是否超时
        uint64_t current_time = get_current_timestamp_ms();
        uint64_t elapsed = current_time - start_time;
        if (elapsed >= (uint64_t)timeout_ms) {
            fcntl(sock, F_SETFL, flags); // 恢复原始模式
            MTR_LOG_DEBUG("receive_icmp_response: timeout after %llu ms, TTL=%d", elapsed, ttl);
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
            fcntl(sock, F_SETFL, flags); // 恢复原始模式
            MTR_LOG_DEBUG("receive_icmp_response: select timeout or error, result=%d, TTL=%d", result, ttl);
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
            MTR_LOG_DEBUG("receive_icmp_response: recvfrom error: %s, TTL=%d", strerror(errno), ttl);
            continue; // 其他错误，继续接收
        }
        
        if (bytes_received < (ssize_t)sizeof(struct mtr_icmphdr)) {
            MTR_LOG_DEBUG("receive_icmp_response: packet too small: %zd bytes, expected at least %zu, TTL=%d", 
                          bytes_received, sizeof(struct mtr_icmphdr), ttl);
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
            MTR_LOG_DEBUG("receive_icmp_response: unsupported address family: %d, TTL=%d", 
                          from_addr.ss_family, ttl);
            continue; // 不支持的地址族，继续接收
        }
        
        MTR_LOG_DEBUG("receive_icmp_response: received %zd bytes from %s, TTL=%d", 
                      bytes_received, temp_src_ip, ttl);
        
        // 解析 ICMP 响应
        int original_ttl = 0;
        int original_seq = 0;
        int is_echo_reply = 0;
        uint16_t icmp_id_value = 0;
        
        if (parse_icmp_response(buffer, (size_t)bytes_received, is_ipv6,
                               &original_ttl, &original_seq, &is_echo_reply, &icmp_id_value) != 0) {
            MTR_LOG_DEBUG("receive_icmp_response: parse_icmp_response failed, from=%s, TTL=%d", 
                          temp_src_ip, ttl);
            continue; // 解析失败，继续接收
        }
        
        MTR_LOG_DEBUG("receive_icmp_response: parsed ICMP response from %s, type=%s, seq=%d, id=%u, expected_seq=%d, expected_id=%u",
                      temp_src_ip, is_echo_reply ? "Echo Reply" : "Time Exceeded/Unreachable",
                      original_seq, icmp_id_value, ttl, expected_id_host);
        
        // 验证 ICMP ID（可选验证，因为内核可能改写 ID）
        // 注意：在 iOS/macOS 上使用 SOCK_DGRAM 时，内核会自动管理 ICMP ID
        // 如果 expected_id_host 为 0，则不验证 ID（主要依赖序列号匹配）
        if (expected_id_host != 0 && icmp_id_value != 0) {
            // 可选：如果提供了期望的 ID，可以验证，但不作为必要条件
            // 因为 NAT/内核可能改写 ID，所以这里不强制要求匹配
            if (icmp_id_value != expected_id_host) {
                MTR_LOG_DEBUG("receive_icmp_response: ID mismatch (received=%u, expected=%u), but continuing (ID may be rewritten by kernel)",
                              icmp_id_value, expected_id_host);
            }
        }
        
        // 验证序列号/TTL。优先使用嵌入的 UDP 目的端口解出的 TTL（original_seq）。
        // 部分设备返回的 ICMP 可能只携带 IP 头中的 TTL（original_ttl）或序列号为 0。
        // 匹配策略：seq==ttl 或 ttl==original_ttl（两者其一即可）。
        if (original_seq != ttl) {
            if (original_ttl != ttl) {
                MTR_LOG_DEBUG("receive_icmp_response: sequence mismatch (seq=%d, ttl_field=%d, expected=%d), from=%s, continuing",
                              original_seq, original_ttl, ttl, temp_src_ip);
                continue; // 序列号和 TTL 都不匹配，继续接收
            } else {
                MTR_LOG_DEBUG("receive_icmp_response: sequence mismatch but ttl_field matches (seq=%d, ttl_field=%d, expected=%d), from=%s",
                              original_seq, original_ttl, ttl, temp_src_ip);
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
        
        MTR_LOG_INFO("receive_icmp_response: matched response from %s, TTL=%d, seq=%d, id=%u, RTT=%.2fms",
                     temp_src_ip, ttl, original_seq, icmp_id_value, *rtt_out);
        
        // 恢复原始 socket 模式
        fcntl(sock, F_SETFL, flags);
        
        return 0;
    }
}

// 接收 UDP 错误消息（从错误队列接收 ICMP Time Exceeded/Destination Unreachable）
// recv_icmp_sock: 可选的 ICMP DGRAM socket，用于接收 ICMP 错误/Time Exceeded
static int receive_udp_error(socket_t udp_sock, socket_t recv_icmp_sock, int timeout_ms, const char *target_ip,
                            int ttl, int is_ipv6, double *rtt_out, char *src_ip_out,
                            uint64_t send_time) {
    if (udp_sock < 0 || !target_ip || !rtt_out) return -1;
    
    MTR_LOG_DEBUG("receive_udp_error: waiting for UDP/ICMP response, target=%s, TTL=%d, timeout=%dms",
                  target_ip, ttl, timeout_ms);
    
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
            MTR_LOG_INFO("receive_udp_error: got ICMP error/time-exceeded via ICMP socket from %s, TTL=%d, RTT=%.2fms",
                         icmp_src_ip, ttl, icmp_rtt);
            return 0;
        }
        MTR_LOG_DEBUG("receive_udp_error: no matching ICMP response via ICMP socket for TTL=%d", ttl);
    }

    // 设置 IP_RECVERR 选项以接收 ICMP 错误消息（iOS 可能不支持，但不影响功能）
    int recverr = 1;
    if (is_ipv6) {
        if (setsockopt(udp_sock, IPPROTO_IPV6, IPV6_RECVERR, &recverr, sizeof(recverr)) < 0) {
            MTR_LOG_DEBUG("receive_udp_error: setsockopt IPV6_RECVERR failed: %s", strerror(errno));
        }
    } else {
        if (setsockopt(udp_sock, IPPROTO_IP, IP_RECVERR, &recverr, sizeof(recverr)) < 0) {
            MTR_LOG_DEBUG("receive_udp_error: setsockopt IP_RECVERR failed: %s", strerror(errno));
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
        // 超时，尝试接收正常的 UDP 响应（可能来自目标）
        char udp_buffer[MTR_RECV_BUFFER_SIZE];
        struct sockaddr_storage from_addr;
        socklen_t from_len = sizeof(from_addr);
        ssize_t bytes = recvfrom(udp_sock, udp_buffer, sizeof(udp_buffer), MSG_DONTWAIT,
                                (struct sockaddr *)&from_addr, &from_len);
        if (bytes >= 0) {
            // 收到 UDP 响应，可能是来自目标
            MTR_LOG_DEBUG("receive_udp_error: recvfrom UDP response bytes=%zd", bytes);
            if (from_addr.ss_family == AF_INET6) {
                struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)&from_addr;
                if (src_ip_out) {
                    inet_ntop(AF_INET6, &addr6->sin6_addr, src_ip_out, INET6_ADDRSTRLEN);
                }
            } else if (from_addr.ss_family == AF_INET) {
                struct sockaddr_in *addr4 = (struct sockaddr_in *)&from_addr;
                if (src_ip_out) {
                    inet_ntop(AF_INET, &addr4->sin_addr, src_ip_out, INET6_ADDRSTRLEN);
                }
            }
            if (src_ip_out && strcmp(src_ip_out, target_ip) == 0) {
                // 来自目标，表示到达目标
                uint64_t receive_time = get_current_timestamp_ms();
                *rtt_out = (double)(receive_time - send_time);
                MTR_LOG_INFO("receive_udp_error: received UDP response from target %s, RTT=%.2fms",
                             src_ip_out, *rtt_out);
                return 0;
            }
        }
        MTR_LOG_DEBUG("receive_udp_error: select timeout or no data for TTL=%d", ttl);
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
        MTR_LOG_DEBUG("receive_udp_error: recvfrom (normal) failed: %s, trying recvmsg", strerror(errno));
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
            MTR_LOG_DEBUG("receive_udp_error: recvmsg failed: %s", strerror(errno));
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
        MTR_LOG_DEBUG("receive_udp_error: recvfrom got %zd bytes from %s", bytes_received,
                      src_ip_out ? src_ip_out : "(unknown)");
    }
    
    MTR_LOG_DEBUG("receive_udp_error: processing received packet bytes=%zd for TTL=%d", bytes_received, ttl);
    
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
static int receive_tcp_error(socket_t tcp_sock, int timeout_ms, const char *target_ip,
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

// 执行单跳探测（完整实现）
static int probe_single_hop(const char *target_ip, const char *protocol, int ttl, 
                            int sequence, int timeout_ms, int is_ipv6, int times,
                            socket_t icmp_socket, socket_t udp_socket, socket_t *tcp_sockets, 
                            size_t tcp_socket_count, cls_mtr_hop_result *hop_result) {
    if (!target_ip || !protocol || !hop_result) return -1;
    
    init_hop_result(hop_result, ttl);
    
    // 限制 times 范围
    if (times < 1) times = 1;
    if (times > 10) times = 10;
    double *rtts = malloc(sizeof(double) * times);
    char **src_ips = malloc(sizeof(char *) * times);
    if (!rtts || !src_ips) {
        if (rtts) free(rtts);
        if (src_ips) free(src_ips);
        return -1;
    }
    
    for (int i = 0; i < times; i++) {
        src_ips[i] = malloc(INET6_ADDRSTRLEN);
        if (!src_ips[i]) {
            for (int j = 0; j < i; j++) free(src_ips[j]);
            free(src_ips);
            free(rtts);
            return -1;
        }
        src_ips[i][0] = '\0';
    }
    
    int rtt_count = 0;
    // 注意：在 iOS/macOS 上使用 SOCK_DGRAM 时，内核会自动管理 ICMP ID
    // 应用程序设置的 ID 可能被内核改写，所以使用固定值 0
    // 接收时主要依赖序列号（TTL）进行匹配，不严格依赖 ID
    uint16_t icmp_identifier = 0;  // 使用固定值，因为内核会改写
    
    for (int i = 0; i < times; i++) {
        uint64_t send_time = 0;
        int send_result = -1;
        double rtt = -1.0;
        char src_ip[INET6_ADDRSTRLEN] = {0};
        
        if (strcmp(protocol, "icmp") == 0) {
            MTR_LOG_DEBUG("probe_single_hop: sending ICMP probe #%d, TTL=%d, sequence=%d", 
                          i + 1, ttl, sequence + i);
            send_result = send_icmp_echo(icmp_socket, target_ip, ttl, sequence + i, 
                                        icmp_identifier, &send_time);
            if (send_result == 0) {
                // 注意：不传递 expected_id（设为 0），因为内核可能改写 ID
                // 主要依赖序列号（TTL）进行匹配。发包在当前线程，收包放到独立线程中执行。
                icmp_receive_params recv_params;
                memset(&recv_params, 0, sizeof(recv_params));
                recv_params.sock = icmp_socket;
                recv_params.timeout_ms = timeout_ms;
                recv_params.target_ip = target_ip;
                recv_params.ttl = ttl;
                recv_params.is_ipv6 = is_ipv6;
                recv_params.send_time = send_time;
                recv_params.expected_id = 0;
                recv_params.rtt_out = -1.0;
                
                pthread_t recv_thread;
                int pthread_ret = pthread_create(&recv_thread, NULL, icmp_receive_thread, &recv_params);
                if (pthread_ret != 0) {
                    MTR_LOG_ERROR("probe_single_hop: failed to create receive thread for probe #%d, TTL=%d, errno=%d",
                                  i + 1, ttl, pthread_ret);
                } else {
                    pthread_join(recv_thread, NULL);
                    
                    if (recv_params.result == 0 && recv_params.src_ip_out[0] != '\0') {
                        MTR_LOG_INFO("probe_single_hop: received ICMP response #%d, TTL=%d, from=%s, RTT=%.2fms",
                                    i + 1, ttl, recv_params.src_ip_out, recv_params.rtt_out);
                        rtts[rtt_count] = recv_params.rtt_out;
                        safe_strncpy(src_ips[rtt_count], recv_params.src_ip_out, INET6_ADDRSTRLEN);
                        rtt_count++;
                    } else {
                        MTR_LOG_DEBUG("probe_single_hop: no ICMP response received for probe #%d, TTL=%d", 
                                      i + 1, ttl);
                    }
                }
            } else {
                MTR_LOG_ERROR("probe_single_hop: failed to send ICMP probe #%d, TTL=%d", 
                              i + 1, ttl);
            }
        } else if (strcmp(protocol, "udp") == 0) {
            uint16_t src_port = 0;
            send_result = send_udp_packet(udp_socket, target_ip, ttl, sequence + i, 
                                          &src_port, &send_time);
            if (send_result == 0) {
                if (receive_udp_error(udp_socket, icmp_socket, timeout_ms, target_ip, ttl, is_ipv6,
                                     &rtt, src_ip, send_time) == 0) {
                    rtts[rtt_count] = rtt;
                    safe_strncpy(src_ips[rtt_count], src_ip, INET6_ADDRSTRLEN);
                    rtt_count++;
                }
            }
        } else if (strcmp(protocol, "tcp") == 0) {
            if (tcp_sockets && tcp_socket_count > 0) {
                socket_t tcp_sock = tcp_sockets[i % tcp_socket_count];
                uint16_t src_port = 0;
                send_result = send_tcp_syn(tcp_sock, target_ip, ttl, sequence + i, 
                                          &src_port, &send_time);
                if (send_result == 0) {
                    if (receive_tcp_error(tcp_sock, timeout_ms, target_ip, ttl, is_ipv6,
                                         &rtt, src_ip, src_port, send_time) == 0) {
                        rtts[rtt_count] = rtt;
                        safe_strncpy(src_ips[rtt_count], src_ip, INET6_ADDRSTRLEN);
                        rtt_count++;
                    }
                }
            }
        }
        
        if (i < times - 1) {
            usleep(200000); // 200ms 间隔
        }
    }
    
    // 计算统计信息
    if (rtt_count > 0) {
        double sum = 0.0;
        double min_rtt = rtts[0];
        double max_rtt = rtts[0];
        char *most_common_ip = src_ips[0];
        int ip_count = 1;
        
        for (int i = 0; i < rtt_count; i++) {
            sum += rtts[i];
            if (rtts[i] < min_rtt) min_rtt = rtts[i];
            if (rtts[i] > max_rtt) max_rtt = rtts[i];
        }
        
        // 找到最常见的 IP 地址
        for (int i = 1; i < rtt_count; i++) {
            int count = 1;
            for (int j = i + 1; j < rtt_count; j++) {
                if (strcmp(src_ips[i], src_ips[j]) == 0) {
                    count++;
                }
            }
            if (count > ip_count) {
                ip_count = count;
                most_common_ip = src_ips[i];
            }
        }
        
        hop_result->latency = sum / rtt_count;
        hop_result->latency_min = min_rtt;
        hop_result->latency_max = max_rtt;
        hop_result->responseNum = rtt_count;
        hop_result->loss = ((double)(times - rtt_count) / times) * 100.0;
        
        // 计算标准差
        double variance = 0.0;
        for (int i = 0; i < rtt_count; i++) {
            double diff = rtts[i] - hop_result->latency;
            variance += diff * diff;
        }
        hop_result->stddev = sqrt(variance / rtt_count);
        
        // 设置最常见的 IP 地址
        safe_strncpy(hop_result->ip, most_common_ip, sizeof(hop_result->ip));
        
        MTR_LOG_INFO("probe_single_hop: TTL=%d completed, responses=%d/%d, IP=%s, loss=%.2f%%, latency=%.2fms (min=%.2f, max=%.2f)",
                     ttl, rtt_count, times, hop_result->ip, hop_result->loss, 
                     hop_result->latency, hop_result->latency_min, hop_result->latency_max);
    } else {
        hop_result->loss = 100.0;
        MTR_LOG_DEBUG("probe_single_hop: TTL=%d failed, no responses received (%d/%d)", 
                      ttl, rtt_count, times);
    }
    
    // 清理
    for (int i = 0; i < times; i++) {
        free(src_ips[i]);
    }
    free(src_ips);
    free(rtts);
    
    return 0;
}

// 创建单个 socket（ICMP/UDP/TCP）
static socket_t create_socket(const char *protocol, int is_ipv6, unsigned int interface_index) {
    socket_t sock = -1;
    int domain = is_ipv6 ? AF_INET6 : AF_INET;
    
    if (strcmp(protocol, "icmp") == 0) {
        sock = socket(domain, SOCK_DGRAM, is_ipv6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP);
        if (sock >= 0) {
            MTR_LOG_DEBUG("create_socket: created ICMP%s socket (fd=%d)", is_ipv6 ? "v6" : "v4", sock);
        }
    } else if (strcmp(protocol, "udp") == 0) {
        sock = socket(domain, SOCK_DGRAM, IPPROTO_UDP);
        if (sock >= 0) {
            MTR_LOG_DEBUG("create_socket: created UDP%s socket (fd=%d)", is_ipv6 ? "v6" : "v4", sock);
        }
    } else if (strcmp(protocol, "tcp") == 0) {
        sock = socket(domain, SOCK_STREAM, IPPROTO_TCP);
        if (sock >= 0) {
            MTR_LOG_DEBUG("create_socket: created TCP%s socket (fd=%d)", is_ipv6 ? "v6" : "v4", sock);
        }
    } else {
        MTR_LOG_ERROR("create_socket: invalid protocol: %s", protocol);
        return -1;
    }
    
    if (sock < 0) {
        MTR_LOG_ERROR("create_socket: failed to create %s%s socket: %s", 
                      protocol, is_ipv6 ? "v6" : "v4", strerror(errno));
        return -1;
    }
    
    // 设置 socket 选项
    int reuse = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    
    // 设置非阻塞模式
    int flags = fcntl(sock, F_GETFL, 0);
    fcntl(sock, F_SETFL, flags | O_NONBLOCK);
    
    // 绑定到指定网络接口（如果提供了接口索引）
    if (interface_index > 0) {
        if (is_ipv6) {
            struct sockaddr_in6 addr6;
            memset(&addr6, 0, sizeof(addr6));
            addr6.sin6_family = AF_INET6;
            addr6.sin6_port = 0;
            addr6.sin6_scope_id = interface_index;
            if (bind(sock, (struct sockaddr *)&addr6, sizeof(addr6)) < 0) {
                close(sock);
                return -1;
            }
        } else {
            struct sockaddr_in addr4;
            memset(&addr4, 0, sizeof(addr4));
            addr4.sin_family = AF_INET;
            addr4.sin_port = 0;
            if (setsockopt(sock, IPPROTO_IP, IP_BOUND_IF, &interface_index, sizeof(interface_index)) < 0) {
                close(sock);
                return -1;
            }
        }
    }
    
    // 恢复阻塞模式（某些操作需要阻塞模式）
    fcntl(sock, F_SETFL, flags);
    
    return sock;
}

// 根据目标地址解析本机源 IP（通过临时 UDP socket 连接获取）
static void resolve_local_ip_for_target(const char *resolved_ip, int is_ipv6, char *out_ip, size_t out_len) {
    if (!resolved_ip || !out_ip || out_len == 0) return;
    
    socket_t tmp_sock = socket(is_ipv6 ? AF_INET6 : AF_INET, SOCK_DGRAM, 0);
    if (tmp_sock < 0) {
        MTR_LOG_DEBUG("resolve_local_ip_for_target: failed to create temp socket: %s", strerror(errno));
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
            MTR_LOG_INFO("resolve_local_ip_for_target: local source IP resolved to %s", out_ip);
        }
    } else {
        MTR_LOG_DEBUG("resolve_local_ip_for_target: connect failed: %s", strerror(errno));
    }
    
    close(tmp_sock);
}

// 执行 MTR 探测的核心逻辑
cls_mtr_detector_error_code cls_mtr_detector_perform_mtr(const char *target,
                                                         const cls_mtr_detector_config * _Nullable config,
                                                         cls_mtr_detector_result *result) {
    if (!target || !result) {
        MTR_LOG_ERROR("cls_mtr_detector_perform_mtr: invalid parameters");
        return cls_mtr_detector_error_invalid_target;
    }
    
    // 解析配置
    const char *protocol = (config && config->protocol) ? config->protocol : "icmp";
    int max_ttl = (config && config->max_ttl > 0) ? config->max_ttl : MTR_DEFAULT_MAX_TTL;
    int timeout_ms = (config && config->timeout_ms > 0) ? config->timeout_ms : MTR_DEFAULT_TIMEOUT_MS;
    int times = (config && config->times > 0) ? config->times : MTR_DEFAULT_TIMES;
    unsigned int interface_index = (config) ? config->interface_index : 0;
    int prefer = (config) ? config->prefer : 0;
    
    MTR_LOG_INFO("cls_mtr_detector_perform_mtr: starting MTR for target=%s, protocol=%s, max_ttl=%d, timeout=%dms, times=%d",
                 target, protocol, max_ttl, timeout_ms, times);
    
    // 限制参数范围
    if (max_ttl < 1) max_ttl = 1;
    if (max_ttl > 255) max_ttl = 255;
    if (timeout_ms < 100) timeout_ms = 100;
    if (timeout_ms > 60000) timeout_ms = 60000;
    if (times < 1) times = 1;
    if (times > 10) times = 10;
    
    // 解析目标地址
    char resolved_ip[INET6_ADDRSTRLEN];
    if (resolve_hostname(target, prefer, resolved_ip) != 0) {
        MTR_LOG_ERROR("cls_mtr_detector_perform_mtr: failed to resolve hostname: %s", target);
        memset(result, 0, sizeof(cls_mtr_detector_result));
        safe_strncpy(result->target, target, sizeof(result->target));
        safe_strncpy(result->method, "mtr", sizeof(result->method));
        result->error_code = cls_mtr_detector_error_resolve_error;
        safe_strncpy(result->error_message, "Failed to resolve hostname", sizeof(result->error_message));
        return cls_mtr_detector_error_resolve_error;
    }
    
    int is_ipv6 = (strchr(resolved_ip, ':') != NULL);
    char device_ip[INET6_ADDRSTRLEN] = {0};
    resolve_local_ip_for_target(resolved_ip, is_ipv6, device_ip, sizeof(device_ip));
    MTR_LOG_INFO("cls_mtr_detector_perform_mtr: resolved %s to %s (%s)", 
                 target, resolved_ip, is_ipv6 ? "IPv6" : "IPv4");
    
    // 初始化结果
    memset(result, 0, sizeof(cls_mtr_detector_result));
    // 保留原始域名/目标
    safe_strncpy(result->target, target, sizeof(result->target));
    safe_strncpy(result->method, "mtr", sizeof(result->method));
    result->max_paths = 1;
    result->paths_capacity = 1;
    result->paths = calloc(1, sizeof(cls_mtr_path_result));
    if (!result->paths) {
        result->error_code = cls_mtr_detector_error_unknown_error;
        return cls_mtr_detector_error_unknown_error;
    }
    result->paths_count = 1;
    
    cls_mtr_path_result *path = &result->paths[0];
    // host 用域名，host_ip 用解析后的 IP
    init_path_result(path, target, protocol, resolved_ip);
    
    // 创建 socket
    socket_t icmp_socket = -1;
    socket_t udp_socket = -1;
    socket_t *tcp_sockets = NULL;
    size_t tcp_socket_count = 0;
    
    if (strcmp(protocol, "icmp") == 0) {
        MTR_LOG_DEBUG("cls_mtr_detector_perform_mtr: creating ICMP socket");
        icmp_socket = create_socket("icmp", is_ipv6, interface_index);
        if (icmp_socket < 0) {
            MTR_LOG_ERROR("cls_mtr_detector_perform_mtr: failed to create ICMP socket");
            result->error_code = cls_mtr_detector_error_socket_create_error;
            safe_strncpy(result->error_message, "Failed to create ICMP socket", sizeof(result->error_message));
            free(result->paths);
            return cls_mtr_detector_error_socket_create_error;
        }
        MTR_LOG_INFO("cls_mtr_detector_perform_mtr: ICMP socket created successfully (fd=%d)", icmp_socket);
    } else if (strcmp(protocol, "udp") == 0) {
        MTR_LOG_DEBUG("cls_mtr_detector_perform_mtr: creating UDP socket");
        udp_socket = create_socket("udp", is_ipv6, interface_index);
        if (udp_socket < 0) {
            result->error_code = cls_mtr_detector_error_socket_create_error;
            safe_strncpy(result->error_message, "Failed to create UDP socket", sizeof(result->error_message));
            free(result->paths);
            return cls_mtr_detector_error_socket_create_error;
        }
        MTR_LOG_INFO("cls_mtr_detector_perform_mtr: UDP socket created successfully (fd=%d)", udp_socket);
        // 额外创建 ICMP socket 用于接收 ICMP 错误/Time Exceeded
        icmp_socket = create_socket("icmp", is_ipv6, interface_index);
        if (icmp_socket < 0) {
            MTR_LOG_ERROR("cls_mtr_detector_perform_mtr: failed to create ICMP recv socket for UDP");
            close(udp_socket);
            free(result->paths);
            result->error_code = cls_mtr_detector_error_socket_create_error;
            safe_strncpy(result->error_message, "Failed to create ICMP recv socket for UDP", sizeof(result->error_message));
            return cls_mtr_detector_error_socket_create_error;
        }
        MTR_LOG_INFO("cls_mtr_detector_perform_mtr: ICMP recv socket for UDP created (fd=%d)", icmp_socket);
    } else if (strcmp(protocol, "tcp") == 0) {
        int socket_count = max_ttl;
        if (socket_count < 10) socket_count = 10;
        if (socket_count > 30) socket_count = 30;
        
        tcp_sockets = malloc(sizeof(socket_t) * socket_count);
        if (!tcp_sockets) {
            result->error_code = cls_mtr_detector_error_socket_create_error;
            safe_strncpy(result->error_message, "Failed to allocate TCP socket array", sizeof(result->error_message));
            free(result->paths);
            return cls_mtr_detector_error_socket_create_error;
        }
        
        for (int i = 0; i < socket_count; i++) {
            tcp_sockets[i] = create_socket("tcp", is_ipv6, interface_index);
            if (tcp_sockets[i] < 0) {
                // 清理已创建的 socket
                for (int j = 0; j < i; j++) {
                    close(tcp_sockets[j]);
                }
                free(tcp_sockets);
                result->error_code = cls_mtr_detector_error_socket_create_error;
                safe_strncpy(result->error_message, "Failed to create TCP socket", sizeof(result->error_message));
                free(result->paths);
                return cls_mtr_detector_error_socket_create_error;
            }
        }
        tcp_socket_count = socket_count;
    } else {
        result->error_code = cls_mtr_detector_error_invalid_target;
        safe_strncpy(result->error_message, "Invalid protocol", sizeof(result->error_message));
        free(result->paths);
        return cls_mtr_detector_error_invalid_target;
    }
    
    // 使用 Network.framework 监控网络状态（可选，用于网络状态检查）
    // 注意：实际的包发送和接收使用 socket，Network.framework 仅用于监控
    
    // 执行逐跳探测
    int last_hop = 0;
    MTR_LOG_INFO("cls_mtr_detector_perform_mtr: starting hop-by-hop probing, max_ttl=%d", max_ttl);
    for (int ttl = 1; ttl <= max_ttl; ttl++) {
        if (ensure_path_results_capacity(path, (size_t)ttl) != 0) {
            MTR_LOG_ERROR("cls_mtr_detector_perform_mtr: failed to allocate memory for hop %d", ttl);
            break;
        }
        
        cls_mtr_hop_result *hop = &path->results[ttl - 1];
        init_hop_result(hop, ttl);
        
        MTR_LOG_INFO("cls_mtr_detector_perform_mtr: probing hop %d (TTL=%d)", ttl, ttl);
        int probe_result = probe_single_hop(resolved_ip, protocol, ttl, 0, timeout_ms, is_ipv6, times,
                                           icmp_socket, udp_socket, tcp_sockets, tcp_socket_count, hop);
        
        if (probe_result == 0 && hop->responseNum > 0) {
            last_hop = ttl;
            path->lastHop = ttl;
            
            MTR_LOG_INFO("cls_mtr_detector_perform_mtr: hop %d completed, IP=%s, responses=%d, loss=%.2f%%",
                        ttl, hop->ip, hop->responseNum, hop->loss);
            
            // 检查是否到达目标
            if (strcmp(hop->ip, resolved_ip) == 0) {
                MTR_LOG_INFO("cls_mtr_detector_perform_mtr: reached target at hop %d, stopping", ttl);
                break; // 到达目标，停止探测
            }
        } else {
            MTR_LOG_DEBUG("cls_mtr_detector_perform_mtr: hop %d failed or no response (responseNum=%d)", 
                         ttl, hop->responseNum);
        }
        
        // 如果连续多次超时，提前停止
        if (ttl > MAX_CONSECUTIVE_TIMEOUTS && hop->responseNum == 0) {
            bool all_timeout = YES;
            for (int i = ttl - MAX_CONSECUTIVE_TIMEOUTS; i < ttl; i++) {
                if (i > 0 && i <= (int)path->results_count) {
                    if (path->results[i - 1].responseNum > 0) {
                        all_timeout = NO;
                        break;
                    }
                }
            }
            if (all_timeout) {
                break;
            }
        }
    }
    
    path->lastHop = last_hop;
    
    // 构造 path 字符串：timestamp:设备源IP-目标IP
    const char *source_ip_for_path = (device_ip[0] != '\0') ? device_ip : "*";
    const char *dest_ip_for_path = path->host_ip[0] ? path->host_ip : path->host;
    snprintf(path->path, sizeof(path->path), "%lld:%s-%s",
             path->timestamp, source_ip_for_path, dest_ip_for_path);
    
    MTR_LOG_INFO("cls_mtr_detector_perform_mtr: MTR completed, lastHop=%d, total_hops=%zu", 
                 last_hop, path->results_count);
    
    // 清理 socket
    if (icmp_socket >= 0) {
        close(icmp_socket);
        MTR_LOG_DEBUG("cls_mtr_detector_perform_mtr: closed ICMP socket");
    }
    if (udp_socket >= 0) {
        close(udp_socket);
        MTR_LOG_DEBUG("cls_mtr_detector_perform_mtr: closed UDP socket");
    }
    if (tcp_sockets) {
        for (size_t i = 0; i < tcp_socket_count; i++) {
            if (tcp_sockets[i] >= 0) close(tcp_sockets[i]);
        }
        free(tcp_sockets);
        MTR_LOG_DEBUG("cls_mtr_detector_perform_mtr: closed %zu TCP sockets", tcp_socket_count);
    }
    
    result->error_code = cls_mtr_detector_error_success;
    MTR_LOG_INFO("cls_mtr_detector_perform_mtr: MTR finished successfully for %s", target);
    return cls_mtr_detector_error_success;
}

// 将 MTR 结果转换为 JSON 格式
int cls_mtr_detector_result_to_json(const cls_mtr_detector_result *result,
                                    cls_mtr_detector_error_code error_code,
                                    char *json_buffer,
                                    size_t buffer_size) {
    if (!result || !json_buffer || buffer_size == 0) {
        return -1;
    }
    
    int written = 0;
    written += snprintf(json_buffer + written, buffer_size - written, "{");
    // net.origin 层（单层键）
    written += snprintf(json_buffer + written, buffer_size - written, "\"net.origin\":{");
    written += snprintf(json_buffer + written, buffer_size - written,
                       "\"method\":\"%s\",", result->method);
    written += snprintf(json_buffer + written, buffer_size - written,
                       "\"host\":\"%s\",", result->target);
    // 首层 type 使用探测协议类型
    const char *top_type = (result->paths_count > 0 && result->paths[0].protocol[0])
                               ? result->paths[0].protocol
                               : "mtr";
    written += snprintf(json_buffer + written, buffer_size - written,
                       "\"type\":\"%s\",", top_type);
    written += snprintf(json_buffer + written, buffer_size - written,
                       "\"max_paths\":%d,", result->max_paths > 0 ? result->max_paths : 1);
    // paths 数组
    written += snprintf(json_buffer + written, buffer_size - written, "\"paths\":[");
    
    for (size_t i = 0; i < result->paths_count; i++) {
        const cls_mtr_path_result *path = &result->paths[i];
        if (i > 0) {
            written += snprintf(json_buffer + written, buffer_size - written, ",");
        }
        written += snprintf(json_buffer + written, buffer_size - written, "{");
        written += snprintf(json_buffer + written, buffer_size - written,
                           "\"method\":\"%s\",", path->method);
        written += snprintf(json_buffer + written, buffer_size - written,
                           "\"host\":\"%s\",", path->host);
        written += snprintf(json_buffer + written, buffer_size - written,
                           "\"host_ip\":\"%s\",", path->host_ip[0] ? path->host_ip : "");
        written += snprintf(json_buffer + written, buffer_size - written,
                           "\"type\":\"path\",");
        // 直接使用已构造的 path（timestamp:源IP-目标IP）
        written += snprintf(json_buffer + written, buffer_size - written,
                           "\"path\":\"%s\",", path->path);
        written += snprintf(json_buffer + written, buffer_size - written,
                           "\"lastHop\":%d,", path->lastHop);
        written += snprintf(json_buffer + written, buffer_size - written,
                           "\"timestamp\":%lld,", path->timestamp);
        written += snprintf(json_buffer + written, buffer_size - written,
                           "\"protocol\":\"%s\",", path->protocol);
        written += snprintf(json_buffer + written, buffer_size - written,
                           "\"exceptionNum\":%d,", path->exceptionNum);
        written += snprintf(json_buffer + written, buffer_size - written,
                           "\"bindFailed\":%d,", path->bindFailed);
        
        // results 数组
        written += snprintf(json_buffer + written, buffer_size - written, "\"result\":[");
        size_t output_count = (path->lastHop > 0) ? (size_t)path->lastHop : path->results_count;
        for (size_t j = 0; j < output_count; j++) {
            const cls_mtr_hop_result *hop = &path->results[j];
            if (j > 0) {
                written += snprintf(json_buffer + written, buffer_size - written, ",");
            }
            written += snprintf(json_buffer + written, buffer_size - written, "{");
            written += snprintf(json_buffer + written, buffer_size - written,
                               "\"loss\":%.2f,", hop->loss);
            written += snprintf(json_buffer + written, buffer_size - written,
                               "\"latency_min\":%.3f,", hop->latency_min);
            written += snprintf(json_buffer + written, buffer_size - written,
                               "\"latency_max\":%.3f,", hop->latency_max);
            written += snprintf(json_buffer + written, buffer_size - written,
                               "\"latency\":%.3f,", hop->latency);
            written += snprintf(json_buffer + written, buffer_size - written,
                               "\"responseNum\":%d,", hop->responseNum);
            written += snprintf(json_buffer + written, buffer_size - written,
                               "\"ip\":\"%s\",", hop->ip[0] ? hop->ip : "*");
            written += snprintf(json_buffer + written, buffer_size - written,
                               "\"hop\":%d,", hop->hop);
            written += snprintf(json_buffer + written, buffer_size - written,
                               "\"stddev\":%.3f", hop->stddev);
            written += snprintf(json_buffer + written, buffer_size - written, "}");
        }
        written += snprintf(json_buffer + written, buffer_size - written, "]");
        written += snprintf(json_buffer + written, buffer_size - written, "}");
    }
    
    written += snprintf(json_buffer + written, buffer_size - written, "]"); // end paths
    written += snprintf(json_buffer + written, buffer_size - written, "}");  // end net.origin
    
    // 可选错误信息
    if (error_code != cls_mtr_detector_error_success || (result->error_message[0] != '\0')) {
        written += snprintf(json_buffer + written, buffer_size - written, ",\"error_code\":%ld", (long)error_code);
        if (result->error_message[0] != '\0') {
            written += snprintf(json_buffer + written, buffer_size - written,
                               ",\"error_message\":\"%s\"", result->error_message);
        }
    }
    
    written += snprintf(json_buffer + written, buffer_size - written, "}"); // end root
    
    return written;
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
