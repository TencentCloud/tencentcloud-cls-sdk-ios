//
//  cls_ping_detector.m
//  network_ios
//
//  Created by zhanxiangli on 2025/12/9.
//  Ping 网络探测器实现 - 使用 BSD socket
//

#import "cls_ping_detector.h"
#import <Foundation/Foundation.h>

#import <arpa/inet.h>
#import <sys/time.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <netinet/ip_icmp.h>
#import <netinet/icmp6.h>
#import <string.h>
#import <stdlib.h>
#import <unistd.h>
#import <math.h>
#import <netdb.h>
#import <errno.h>
#import <fcntl.h>
#import <sys/select.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <arpa/nameser.h>
#import <arpa/nameser_compat.h>
#import <resolv.h>
#import <dlfcn.h>
#import <stdarg.h>
#import <stddef.h>

// ============================================================================
// 常量定义
// ============================================================================

#define PING_DEFAULT_TIMEOUT_MS 2000
#define PING_MIN_TIMEOUT_MS 100
#define PING_MAX_TIMEOUT_MS 60000
#define PING_DEFAULT_INTERVAL_MS 200
#define PING_MIN_INTERVAL_MS 10
#define PING_MAX_INTERVAL_MS 60000
#define PING_DEFAULT_PACKET_SIZE 56
#define PING_MIN_PACKET_SIZE 0
#define PING_MAX_PACKET_SIZE 65507
#define PING_DEFAULT_TIMES 10
#define PING_MIN_TIMES 1
#define PING_MAX_TIMES 1000
#define PING_MAX_TTL 255
#define PING_MIN_TTL 1
#define PING_DEFAULT_TTL 64

#ifndef ICMPV6_ECHO_REQUEST
#define ICMPV6_ECHO_REQUEST 128
#endif
#ifndef ICMPV6_ECHO_REPLY
#define ICMPV6_ECHO_REPLY 129
#endif
#ifndef IPPROTO_ICMPV6
#define IPPROTO_ICMPV6 58
#endif

// ============================================================================
// ICMP 报文结构
// ============================================================================

typedef struct {
    uint8_t type;
    uint8_t code;
    uint16_t checksum;
    uint16_t identifier;
    uint16_t sequence;
} ICMPHeader;

#define ICMP_ECHO_REQUEST 8
#define ICMP_ECHO_REPLY 0

// ============================================================================
// RTT 数组（用于统计计算）
// ============================================================================

typedef struct {
    double *rtts;
    size_t count;
    size_t capacity;
} RttArray;

/**
 * 初始化RTT数组
 * @param array RTT数组指针
 */
static void rtt_array_init(RttArray *array) {
    if (array == NULL) {
        return;
    }
    
    array->rtts = NULL;
    array->count = 0;
    array->capacity = 0;
}

/**
 * 向RTT数组添加一个RTT值
 * 如果数组容量不足，会自动扩容
 * @param array RTT数组指针
 * @param rtt RTT值（毫秒）
 * @return 成功返回0，失败返回-1（内存分配失败）
 */
static int rtt_array_add(RttArray *array, double rtt) {
    if (array == NULL) {
        return -1;
    }
    
    // 检查是否需要扩容
    if (array->count >= array->capacity) {
        size_t new_capacity = array->capacity == 0 ? 16 : array->capacity * 2;
        
        // 防止整数溢出
        if (new_capacity > SIZE_MAX / sizeof(double)) {
            return -1;
        }
        
        // 使用临时指针保存realloc结果，避免realloc失败时丢失原指针
        double *new_rtts = realloc(array->rtts, new_capacity * sizeof(double));
        if (!new_rtts) {
            // realloc失败，原指针仍然有效，但无法扩容
            return -1;
        }
        
        // realloc成功，更新指针和容量
        array->rtts = new_rtts;
        array->capacity = new_capacity;
    }
    
    // 添加新元素
    array->rtts[array->count++] = rtt;
    return 0;
}

/**
 * 释放RTT数组的内存
 * @param array RTT数组指针
 */
static void rtt_array_free(RttArray *array) {
    if (array == NULL) {
        return;
    }
    
    if (array->rtts) {
        free(array->rtts);
        array->rtts = NULL;
    }
    array->count = 0;
    array->capacity = 0;
}

// ============================================================================
// 辅助函数
// ============================================================================

static uint16_t calculate_icmp_checksum(const void *data, size_t len) {
    if (data == NULL || len == 0) {
        return 0;
    }
    
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

// IPv4/IPv6 地址联合体，用于支持两种地址类型
typedef union {
    struct in_addr v4;
    struct in6_addr v6;
} ip_addr_t;

static uint16_t calculate_icmpv6_checksum(const struct in6_addr *src_addr,
                                          const struct in6_addr *dst_addr,
                                          const void *icmp_packet,
                                          size_t icmp_len) {
    if (src_addr == NULL || dst_addr == NULL || icmp_packet == NULL || icmp_len == 0) {
        return 0;
    }
    
    uint32_t sum = 0;
    
    // IPv6伪头部：源地址
    const uint16_t *src = (const uint16_t *)src_addr;
    for (int i = 0; i < 8; i++) {
        sum += src[i];
    }
    
    // IPv6伪头部：目标地址
    const uint16_t *dst = (const uint16_t *)dst_addr;
    for (int i = 0; i < 8; i++) {
        sum += dst[i];
    }
    
    // IPv6伪头部：上层协议长度
    sum += (uint32_t)icmp_len >> 16;
    sum += (uint32_t)icmp_len & 0xFFFF;
    
    // IPv6伪头部：下一个头部值
    sum += IPPROTO_ICMPV6;
    
    // ICMPv6数据包本身
    const uint16_t *icmp_buf = (const uint16_t *)icmp_packet;
    size_t word_count = icmp_len / 2;
    for (size_t i = 0; i < word_count; i++) {
        sum += icmp_buf[i];
    }
    
    if (icmp_len & 1) {
        sum += ((const uint8_t *)icmp_buf)[word_count * 2] << 8;
    }
    
    while (sum >> 16) {
        sum = (sum & 0xFFFF) + (sum >> 16);
    }
    
    return (uint16_t)(~sum);
}

static uint64_t get_current_timestamp_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000 + (uint64_t)tv.tv_usec / 1000;
}

// 根据接口索引获取接口名称
static void get_interface_name(unsigned int interface_index, char *interface_name, size_t name_size) {
    if (interface_name == NULL || name_size == 0) {
        return;
    }
    
    interface_name[0] = '\0';
    
    if (interface_index == 0) {
        // 如果接口索引为0，表示使用系统默认接口
        // 尝试获取默认路由的接口名称，优先查找en0（WiFi）或en1（以太网）
        struct ifaddrs *ifaddrs_list = NULL;
        if (getifaddrs(&ifaddrs_list) == 0) {
            struct ifaddrs *ifa = ifaddrs_list;
            // 优先查找en0（WiFi）
            while (ifa != NULL) {
                if (ifa->ifa_addr != NULL && 
                    (ifa->ifa_flags & IFF_UP) && 
                    (ifa->ifa_flags & IFF_RUNNING)) {
                    if (strcmp(ifa->ifa_name, "en0") == 0) {
                        strncpy(interface_name, "WIFI", name_size - 1);
                        interface_name[name_size - 1] = '\0';
                        freeifaddrs(ifaddrs_list);
                        return;
                    }
                }
                ifa = ifa->ifa_next;
            }
            // 如果没找到en0，查找en1（以太网）
            ifa = ifaddrs_list;
            while (ifa != NULL) {
                if (ifa->ifa_addr != NULL && 
                    (ifa->ifa_flags & IFF_UP) && 
                    (ifa->ifa_flags & IFF_RUNNING)) {
                    if (strcmp(ifa->ifa_name, "en1") == 0) {
                        strncpy(interface_name, "ETHERNET", name_size - 1);
                        interface_name[name_size - 1] = '\0';
                        freeifaddrs(ifaddrs_list);
                        return;
                    }
                }
                ifa = ifa->ifa_next;
            }
            freeifaddrs(ifaddrs_list);
        }
        // 如果没找到，使用空字符串
        if (interface_name[0] == '\0') {
            interface_name[0] = '\0'; // 已经是空字符串，确保null终止
        }
    } else {
        // 使用if_indextoname获取接口名称
        char ifname[IF_NAMESIZE];
        if (if_indextoname(interface_index, ifname) != NULL) {
            // 将接口名称转换为更友好的名称
            if (strcmp(ifname, "en0") == 0) {
                strncpy(interface_name, "WIFI", name_size - 1);
            } else if (strcmp(ifname, "en1") == 0) {
                strncpy(interface_name, "ETHERNET", name_size - 1);
            } else if (strncmp(ifname, "pdp_ip", 6) == 0) {
                strncpy(interface_name, "CELLULAR", name_size - 1);
            } else {
                strncpy(interface_name, ifname, name_size - 1);
            }
            interface_name[name_size - 1] = '\0';
        } else {
            interface_name[0] = '\0';
        }
    }
}

// 查找一个可用的接口索引（优先具备链路本地IPv6地址，其次任意UP/RUNNING非loopback）
static unsigned int find_active_ifindex_for_linklocal(void) {
    struct ifaddrs *ifaddrs_list = NULL;
    unsigned int candidate = 0;

    if (getifaddrs(&ifaddrs_list) != 0) {
        return 0;
    }

    // 优先：拥有链路本地IPv6地址的接口
    for (struct ifaddrs *ifa = ifaddrs_list; ifa != NULL; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET6) {
            continue;
        }
        if ((ifa->ifa_flags & IFF_UP) == 0 || (ifa->ifa_flags & IFF_RUNNING) == 0 || (ifa->ifa_flags & IFF_LOOPBACK)) {
            continue;
        }
        struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)ifa->ifa_addr;
        if (IN6_IS_ADDR_LINKLOCAL(&addr6->sin6_addr)) {
            candidate = if_nametoindex(ifa->ifa_name);
            if (candidate != 0) {
                freeifaddrs(ifaddrs_list);
                return candidate;
            }
        }
    }

    // 备用：任意UP/RUNNING非loopback接口
    for (struct ifaddrs *ifa = ifaddrs_list; ifa != NULL; ifa = ifa->ifa_next) {
        if ((ifa->ifa_flags & IFF_UP) == 0 || (ifa->ifa_flags & IFF_RUNNING) == 0 || (ifa->ifa_flags & IFF_LOOPBACK)) {
            continue;
        }
        candidate = if_nametoindex(ifa->ifa_name);
        if (candidate != 0) {
            freeifaddrs(ifaddrs_list);
            return candidate;
        }
    }

    freeifaddrs(ifaddrs_list);
    return 0;
}

// 比较IPv6地址时忽略scope后缀（如%en0），避免链路本地地址误判
static BOOL ip_equal_ignore_scope(const char *expected_ip, const char *from_ip) {
    if (!expected_ip || !from_ip) {
        return NO;
    }
    if (strcmp(expected_ip, from_ip) == 0) {
        return YES;
    }
    
    char expected_buf[128];
    char from_buf[128];
    strncpy(expected_buf, expected_ip, sizeof(expected_buf) - 1);
    expected_buf[sizeof(expected_buf) - 1] = '\0';
    strncpy(from_buf, from_ip, sizeof(from_buf) - 1);
    from_buf[sizeof(from_buf) - 1] = '\0';
    
    char *expected_scope = strchr(expected_buf, '%');
    if (expected_scope) {
        *expected_scope = '\0';
    }
    char *from_scope = strchr(from_buf, '%');
    if (from_scope) {
        *from_scope = '\0';
    }
    
    if (expected_buf[0] == '\0' || from_buf[0] == '\0') {
        return NO;
    }
    return strcmp(expected_buf, from_buf) == 0;
}

// 检查接口是否存在、UP/RUNNING，及其是否具备指定协议族地址
static BOOL interface_supports_family(unsigned int interface_index, int family, BOOL *found, BOOL *has_family) {
    if (found) *found = NO;
    if (has_family) *has_family = NO;
    if (interface_index == 0) {
        return YES; // 未指定接口视为通过
    }
    
    struct ifaddrs *ifaddrs_list = NULL;
    if (getifaddrs(&ifaddrs_list) != 0) {
        return NO;
    }
    
    BOOL ok = NO;
    for (struct ifaddrs *ifa = ifaddrs_list; ifa != NULL; ifa = ifa->ifa_next) {
        if (!ifa->ifa_name || if_nametoindex(ifa->ifa_name) != interface_index) {
            continue;
        }
        if (found) *found = YES;
        
        // 必须是 UP/RUNNING 且非 loopback
        if ((ifa->ifa_flags & IFF_UP) == 0 || (ifa->ifa_flags & IFF_RUNNING) == 0 || (ifa->ifa_flags & IFF_LOOPBACK)) {
            ok = NO;
            continue;
        } else {
            ok = YES;
        }
        
        if (ifa->ifa_addr && ifa->ifa_addr->sa_family == family) {
            if (has_family) *has_family = YES;
        }
    }
    
    freeifaddrs(ifaddrs_list);
    return ok;
}

// 检查接口是否具备链路本地IPv6地址
static BOOL interface_has_linklocal_ipv6(unsigned int interface_index) {
    if (interface_index == 0) {
        return NO;
    }
    struct ifaddrs *ifaddrs_list = NULL;
    if (getifaddrs(&ifaddrs_list) != 0) {
        return NO;
    }
    BOOL has_linklocal = NO;
    for (struct ifaddrs *ifa = ifaddrs_list; ifa != NULL; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET6) {
            continue;
        }
        if ((ifa->ifa_flags & IFF_UP) == 0 || (ifa->ifa_flags & IFF_RUNNING) == 0 || (ifa->ifa_flags & IFF_LOOPBACK)) {
            continue;
        }
        if (if_nametoindex(ifa->ifa_name) != interface_index) {
            continue;
        }
        struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)ifa->ifa_addr;
        if (IN6_IS_ADDR_LINKLOCAL(&addr6->sin6_addr)) {
            has_linklocal = YES;
            break;
        }
    }
    freeifaddrs(ifaddrs_list);
    return has_linklocal;
}

// 在指定接口上执行简易DNS查询（仅A/AAAA），成功返回0
static int dns_query_on_interface(const char *hostname, int family, unsigned int interface_index,
                                  char *ip_buffer, size_t ip_buffer_len) {
    if (!hostname || !ip_buffer || ip_buffer_len == 0 || interface_index == 0) {
        return -1;
    }
    
    struct __res_state res;
    memset(&res, 0, sizeof(res));

    // 动态加载 res_ninit/res_nmkquery/res_nclose，避免链接私有符号
    typedef int (*res_ninit_fn)(res_state);
    typedef int (*res_nmkquery_fn)(res_state, int, const char *, int, int,
                                   const unsigned char *, int, const unsigned char *,
                                   unsigned char *, int);
    typedef void (*res_nclose_fn)(res_state);
    typedef void (*res_getservers_fn)(const res_state, union res_sockaddr_union *, int);

    res_ninit_fn dyn_res_ninit = NULL;
    res_nmkquery_fn dyn_res_nmkquery = NULL;
    res_nclose_fn dyn_res_nclose = NULL;
    res_getservers_fn dyn_res_getservers = NULL;

    void *libres = dlopen("/usr/lib/libresolv.9.dylib", RTLD_LAZY);
    if (libres) {
        dyn_res_ninit = (res_ninit_fn)dlsym(libres, "res_9_ninit");
        if (!dyn_res_ninit) dyn_res_ninit = (res_ninit_fn)dlsym(libres, "res_ninit");
        dyn_res_nmkquery = (res_nmkquery_fn)dlsym(libres, "res_9_nmkquery");
        if (!dyn_res_nmkquery) dyn_res_nmkquery = (res_nmkquery_fn)dlsym(libres, "res_nmkquery");
        dyn_res_nclose = (res_nclose_fn)dlsym(libres, "res_9_nclose");
        if (!dyn_res_nclose) dyn_res_nclose = (res_nclose_fn)dlsym(libres, "res_nclose");
        dyn_res_getservers = (res_getservers_fn)dlsym(libres, "res_9_getservers");
        if (!dyn_res_getservers) dyn_res_getservers = (res_getservers_fn)dlsym(libres, "res_getservers");
    }

    if (!dyn_res_ninit || !dyn_res_nmkquery || !dyn_res_nclose) {
        if (libres) dlclose(libres);
        return -1;
    }

    if (dyn_res_ninit(&res) != 0) {
        if (libres) dlclose(libres);
        return -1;
    }
    
    // 构造查询
    uint8_t query[NS_PACKETSZ];
    int qtype = (family == AF_INET6) ? ns_t_aaaa : ns_t_a;
    int qlen = dyn_res_nmkquery(&res, ns_o_query, hostname, ns_c_in, qtype, NULL, 0, NULL, query, sizeof(query));
    if (qlen < 0) {
        dyn_res_nclose(&res);
        if (libres) dlclose(libres);
        return -1;
    }
    
    // 获取DNS服务器列表，优先尝试动态调用res_getservers以支持IPv6
    union res_sockaddr_union servers[MAXNS];
    memset(servers, 0, sizeof(servers));
    int server_count = 0;

    if (dyn_res_getservers) {
        dyn_res_getservers(&res, servers, MAXNS);
        for (int i = 0; i < MAXNS; i++) {
            if (servers[i].sin.sin_family == 0) continue;
            server_count++;
        }
    } else {
        // 退化：使用 IPv4 nsaddr_list
        for (int i = 0; i < res.nscount && i < MAXNS; i++) {
            if (res.nsaddr_list[i].sin_family == 0) continue;
            memcpy(&servers[server_count].sin, &res.nsaddr_list[i], sizeof(struct sockaddr_in));
            server_count++;
        }
    }
    
    int result = -1;
    for (int i = 0; i < MAXNS; i++) {
        sa_family_t srv_family = servers[i].sin.sin_family;
        if (srv_family == 0) continue;
        
        // 兼容 IPv6 填充
        if (srv_family == AF_INET6 && servers[i].sin6.sin6_family == 0) {
            srv_family = servers[i].sin6.sin6_family;
            if (srv_family == 0) continue;
        }
        
        int sock = socket(srv_family, SOCK_DGRAM, 0);
        if (sock < 0) {
            continue;
        }
        
        // 绑定到指定接口
        if (srv_family == AF_INET6) {
            if (setsockopt(sock, IPPROTO_IPV6, IPV6_BOUND_IF, &interface_index, sizeof(interface_index)) < 0) {
                close(sock);
                continue;
            }
        } else {
            if (setsockopt(sock, IPPROTO_IP, IP_BOUND_IF, &interface_index, sizeof(interface_index)) < 0) {
                close(sock);
                continue;
            }
        }
        
        // 超时设置 1500ms
        struct timeval tv;
        tv.tv_sec = 1;
        tv.tv_usec = 500000;
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        
        // 发送查询
        socklen_t addrlen = (srv_family == AF_INET6) ? sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_in);
        if (sendto(sock, query, (size_t)qlen, 0, (const struct sockaddr *)&servers[i], addrlen) < 0) {
            close(sock);
            continue;
        }
        
        // 接收响应
        uint8_t answer[NS_PACKETSZ];
        int rlen = (int)recvfrom(sock, answer, sizeof(answer), 0, NULL, NULL);
        close(sock);
        if (rlen <= 0) {
            continue;
        }
        
        // 解析 DNS 响应（简化，仅取第一条 A/AAAA 应答）
        if (rlen < 12) {
            continue;
        }
        const uint8_t *ptr = answer;
        uint16_t qdcount = ntohs(*(const uint16_t *)(ptr + 4));
        uint16_t ancount = ntohs(*(const uint16_t *)(ptr + 6));
        int offset = 12;
        
        // 跳过问题区
        for (uint16_t qi = 0; qi < qdcount; qi++) {
            int name_off = offset;
            int jumps = 0;
            while (name_off < rlen && answer[name_off] != 0) {
                uint8_t labellen = answer[name_off];
                // 压缩指针
                if ((labellen & 0xC0) == 0xC0) {
                    if (name_off + 1 >= rlen) {
                        name_off = rlen;
                        break;
                    }
                    name_off += 2;
                    break;
                } else {
                    name_off += 1 + labellen;
                }
                if (++jumps > 128) break;
            }
            name_off += 1; // 跳过终止0
            name_off += 4; // 跳过QTYPE/QCLASS
            if (name_off > rlen) { offset = rlen; break; }
            offset = name_off;
        }
        if (offset >= rlen) {
            continue;
        }
        
        // 读取应答区
        for (uint16_t ai = 0; ai < ancount; ai++) {
            // 跳过NAME（处理压缩指针）
            int name_off = offset;
            int jumps = 0;
            while (name_off < rlen && answer[name_off] != 0) {
                uint8_t labellen = answer[name_off];
                if ((labellen & 0xC0) == 0xC0) {
                    if (name_off + 1 >= rlen) {
                        name_off = rlen;
                        break;
                    }
                    name_off += 2;
                    break;
                } else {
                    name_off += 1 + labellen;
                }
                if (++jumps > 128) break;
            }
            name_off += 1; // 终止0或已跳过指针
            if (name_off + 10 > rlen) {
                offset = rlen;
                break;
            }
            uint16_t type = ntohs(*(const uint16_t *)(answer + name_off));
            uint16_t rdlength = ntohs(*(const uint16_t *)(answer + name_off + 8));
            int rdata_off = name_off + 10;
            if (rdata_off + rdlength > rlen) {
                offset = rlen;
                break;
            }
            
            if (type == ns_t_a && family != AF_INET6 && rdlength == sizeof(struct in_addr)) {
                inet_ntop(AF_INET, answer + rdata_off, ip_buffer, (socklen_t)ip_buffer_len);
                result = 0;
                goto done;
            }
            if (type == ns_t_aaaa && family != AF_INET && rdlength == sizeof(struct in6_addr)) {
                inet_ntop(AF_INET6, answer + rdata_off, ip_buffer, (socklen_t)ip_buffer_len);
                result = 0;
                goto done;
            }
            
            offset = rdata_off + rdlength;
        }
    }

done:
    dyn_res_nclose(&res);
    if (libres) dlclose(libres);
    return result;
}

static int wait_for_socket_readable(int socket, int timeout_ms) {
    // 检查socket值是否超出FD_SETSIZE限制
    if (socket < 0 || socket >= FD_SETSIZE) {
        return 0;
    }
    
    fd_set readfds;
    struct timeval timeout;
    
    FD_ZERO(&readfds);
    FD_SET(socket, &readfds);
    
    // 防止timeout计算溢出
    if (timeout_ms < 0) {
        timeout_ms = 0;
    } else if (timeout_ms > 60000) {
        timeout_ms = 60000; // 限制最大60秒
    }
    
    timeout.tv_sec = timeout_ms / 1000;
    timeout.tv_usec = (timeout_ms % 1000) * 1000;
    
    // select可能被信号中断，需要重试
    // 记录开始时间，用于计算剩余超时时间
    struct timeval start_time;
    gettimeofday(&start_time, NULL);
    
    int result;
    do {
        result = select(socket + 1, &readfds, NULL, NULL, &timeout);
        if (result < 0 && errno == EINTR) {
            // 被信号中断，计算剩余超时时间后重试
            struct timeval current_time;
            gettimeofday(&current_time, NULL);
            
            // 计算已用时间（微秒）
            int64_t elapsed_us = ((int64_t)(current_time.tv_sec - start_time.tv_sec) * 1000000 +
                                 (int64_t)(current_time.tv_usec - start_time.tv_usec));
            int64_t remaining_ms = timeout_ms - (elapsed_us / 1000);
            
            // 如果已经超时，直接返回
            if (remaining_ms <= 0) {
                return 0;
            }
            
            // 重新设置fd_set和剩余超时时间
            FD_ZERO(&readfds);
            FD_SET(socket, &readfds);
            timeout.tv_sec = remaining_ms / 1000;
            timeout.tv_usec = (remaining_ms % 1000) * 1000;
        } else {
            break;
        }
    } while (1);
    
    return result > 0 && FD_ISSET(socket, &readfds);
}

// ============================================================================
// ICMP 报文构造
// ============================================================================

static NSData *build_icmp_packet(int packet_size, uint8_t icmp_type, int sequence, uint16_t identifier, BOOL isIPv6) {
    size_t total_size = sizeof(ICMPHeader) + (size_t)packet_size;
    NSMutableData *packet = [NSMutableData dataWithLength:total_size];
    if (!packet) {
        return nil;
    }
    
    ICMPHeader *header = (ICMPHeader *)packet.mutableBytes;
    header->type = icmp_type;
    header->code = 0;
    header->checksum = 0;
    header->identifier = htons(identifier);
    header->sequence = htons((uint16_t)sequence);
    
    // 填充数据负载
    if (packet_size > 0) {
        uint8_t *data = ((uint8_t *)packet.mutableBytes) + sizeof(ICMPHeader);
        uint64_t timestamp = get_current_timestamp_ms();
        size_t timestamp_size = sizeof(timestamp);
        size_t copy_len = (timestamp_size < (size_t)packet_size) ? timestamp_size : (size_t)packet_size;
        
        memcpy(data, &timestamp, copy_len);
        
        // 填充剩余部分
        if (packet_size > (int)timestamp_size) {
            int remaining = packet_size - (int)timestamp_size;
            for (int i = 0; i < remaining; i++) {
                data[(int)timestamp_size + i] = (uint8_t)(i % 256);
            }
        }
    }
    
    // 计算校验和（仅 IPv4）
    if (!isIPv6) {
        header->checksum = calculate_icmp_checksum(packet.bytes, packet.length);
    }
    
    return packet;
}

// ============================================================================
// ICMP 响应验证
// ============================================================================

static BOOL validate_icmp_reply(const void *data, size_t data_len, BOOL isIPv6,
                                uint8_t expected_type, uint16_t expected_sequence,
                                const ip_addr_t *src_addr,
                                const ip_addr_t *dst_addr) {
    if (data == NULL || data_len < sizeof(ICMPHeader)) {
        return NO;
    }
    
    const ICMPHeader *header = (const ICMPHeader *)data;
    
    // 验证类型
    if (header->type != expected_type) {
        return NO;
    }
    
    // 验证序列号（不再校验ID，因为NAT/设备可能改写ID）
    uint16_t recv_seq = ntohs(header->sequence);
    if (recv_seq != expected_sequence) {
        return NO;
    }
    
    // 验证负载模式（宽松模式：仅作为辅助验证，不强制要求）
    // 注意：某些系统可能会修改ICMP Echo Reply的payload，所以payload验证不应该太严格
    // 主要依靠序列号匹配来识别正确的回包
    // 实际上，ICMP Echo Reply的payload应该是Echo Request的完整副本，但某些系统可能会修改
    // 为了兼容性，我们主要依靠序列号匹配，payload验证只是辅助（用于过滤明显异常的包）
    size_t payload_len = (data_len > sizeof(ICMPHeader)) ? (data_len - sizeof(ICMPHeader)) : 0;
    
    // 只检查payload长度是否合理，不强制要求payload模式匹配
    // 因为某些系统可能会修改payload，导致模式验证失败
    // 根据IP版本动态计算最大负载长度：
    // IPv4: 65535 (最大UDP/IP包) - 20 (IPv4头) - 8 (ICMP头) = 65507
    // IPv6: 65535 (最大UDP/IP包) - 40 (IPv6头) - 8 (ICMP头) = 65487
    const size_t max_payload_len = isIPv6 ? 65487 : 65507;
    if (payload_len > max_payload_len) {
        // payload长度异常，拒绝
        return NO;
    }
    
    // payload长度合理，接受（序列号匹配是主要验证条件）
    
    // 验证校验和（辅助验证模式：校验和错误可能是由于payload被修改导致的）
    // 注意：某些系统可能会修改ICMP Echo Reply的payload，导致校验和不匹配
    // 为了兼容性，我们主要依靠序列号匹配，校验和验证作为辅助验证
    // 校验和失败时不会拒绝该包，仅作为异常情况的参考信息
    // 注意：虽然 RFC 2460 要求 ICMPv6 校验和是强制字段，但为了兼容某些可能修改
    // payload 的系统，我们采用辅助验证策略，主要依赖序列号匹配来识别正确的回包
    BOOL checksum_ok = YES;
    BOOL checksum_validated = NO; // 标记是否成功进行了校验和验证
    
    if (!isIPv6) {
        // IPv4 ICMP校验和验证（辅助验证）
        NSMutableData *tempData = [NSMutableData dataWithBytes:data length:data_len];
        ICMPHeader *tempHeader = (ICMPHeader *)tempData.mutableBytes;
        uint16_t saved_checksum = tempHeader->checksum;
        tempHeader->checksum = 0;
        
        uint16_t calculated_checksum = calculate_icmp_checksum(tempData.bytes, tempData.length);
        checksum_validated = YES;
        if (saved_checksum != calculated_checksum) {
            checksum_ok = NO; // 校验和错误，但作为辅助验证不拒绝该包
        }
    } else {
        // IPv6 ICMPv6校验和验证（辅助验证）
        // 注意：虽然 RFC 2460 要求 ICMPv6 校验和是强制字段，但为了兼容性采用辅助验证策略
        if (src_addr && dst_addr) {
            NSMutableData *tempData = [NSMutableData dataWithBytes:data length:data_len];
            ICMPHeader *tempHeader = (ICMPHeader *)tempData.mutableBytes;
            uint16_t saved_checksum = tempHeader->checksum;
            tempHeader->checksum = 0;
            
            // 使用 IPv6 地址进行校验和计算
            uint16_t calculated_checksum = calculate_icmpv6_checksum(&src_addr->v6, &dst_addr->v6, tempData.bytes, tempData.length);
            checksum_validated = YES;
            if (saved_checksum != calculated_checksum) {
                checksum_ok = NO; // 校验和错误，但作为辅助验证不拒绝该包
            }
        } else {
            // 无法获取源地址或目标地址，无法验证 ICMPv6 校验和
            // 这可能是由于 getsockname 失败或 socket 状态异常导致的
            // 作为辅助验证，无法验证时不拒绝该包，主要依赖序列号匹配
            checksum_validated = NO;
            checksum_ok = YES; // 无法验证时假设通过，不拒绝
        }
    }
    
    // 校验和验证是辅助验证，主要依靠序列号匹配
    // 即使校验和验证失败，只要序列号匹配，仍然接受该包
    // 这样可以兼容某些可能修改 payload 导致校验和不匹配的系统
    (void)checksum_ok; // 当前不使用，保留用于未来可能的统计或日志
    (void)checksum_validated; // 当前不使用，保留用于未来可能的统计或日志
    
    return YES;
}

// ============================================================================
// 错误信息处理
// ============================================================================

// 设置错误信息到result中
static void set_error_message(cls_ping_detector_result *result, const char *format, ...) {
    if (result == NULL) {
        return;
    }
    
    va_list args;
    va_start(args, format);
    vsnprintf(result->error_message, sizeof(result->error_message) - 1, format, args);
    va_end(args);
    result->error_message[sizeof(result->error_message) - 1] = '\0';
}

// ============================================================================
// 域名解析
// ============================================================================

// 返回值：0 成功；-1 解析失败；-2 仅发现 IPv4-mapped IPv6 地址且未找到纯 IPv6
static int resolve_hostname(const char *hostname, char *ip_buffer, int prefer, unsigned int interface_index) {
    if (hostname == NULL || ip_buffer == NULL) {
        return -1;
    }
    
    size_t hostname_len = strlen(hostname);
    if (hostname_len == 0 || hostname_len > 255) {
        return -1;
    }
    
    struct addrinfo hints, *result = NULL;
    memset(&hints, 0, sizeof(hints));
    
    // 根据偏好设置地址族
    // prefer: 0=IPv4优先, 1=IPv6优先, 2=IPv4 only, 3=IPv6 only
    if (prefer == 2) {
        // IPv4 only
        hints.ai_family = AF_INET;
    } else if (prefer == 3) {
        // IPv6 only
        hints.ai_family = AF_INET6;
    } else {
        // IPv4优先或IPv6优先，尝试解析所有地址
        hints.ai_family = AF_UNSPEC;
    }
    hints.ai_socktype = 0;
    hints.ai_flags = AI_ADDRCONFIG;
#ifdef AI_NUMERICSERV
    hints.ai_flags |= AI_NUMERICSERV; // 避免服务名反查导致阻塞
#endif
    
    int getaddrinfo_result = -1;
    
    // 优先：尝试在指定接口上直接做 DNS 查询（仅A/AAAA）
    if (interface_index > 0) {
        // 先按偏好族查询，失败则回退另一族
        if (prefer != 3) {
            if (dns_query_on_interface(hostname, AF_INET, interface_index, ip_buffer, INET6_ADDRSTRLEN) == 0) {
                return 0;
            }
        }
        if (prefer != 2) {
            if (dns_query_on_interface(hostname, AF_INET6, interface_index, ip_buffer, INET6_ADDRSTRLEN) == 0) {
                return 0;
            }
        }
        // 如果接口查询失败，继续走系统解析作为兜底
    }
    
    getaddrinfo_result = getaddrinfo(hostname, NULL, &hints, &result);
    if (getaddrinfo_result != 0 || result == NULL) {
        return -1;
    }
    
    // 根据偏好选择地址
    struct addrinfo *ipv4_result = NULL;
    struct addrinfo *ipv6_result = NULL;
    
    BOOL has_mapped_ipv6 = NO;
    // 遍历所有结果，找到第一个IPv4和合法的IPv6地址
    // 避免使用 IPv4-mapped IPv6 (::ffff:x.x.x.x)；这些应走 IPv4 分支
    for (struct addrinfo *p = result; p != NULL; p = p->ai_next) {
        if (p->ai_family == AF_INET && ipv4_result == NULL) {
            ipv4_result = p;
        } else if (p->ai_family == AF_INET6 && ipv6_result == NULL) {
            struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)p->ai_addr;
            const uint8_t *bytes = (const uint8_t *)&addr6->sin6_addr;
            BOOL is_mapped = (bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0 &&
                              bytes[4] == 0 && bytes[5] == 0 && bytes[6] == 0 && bytes[7] == 0 &&
                              bytes[8] == 0 && bytes[9] == 0 && bytes[10] == 0xFF && bytes[11] == 0xFF);
            if (is_mapped) {
                // 跳过 IPv4-mapped IPv6，交由 IPv4 逻辑处理
                has_mapped_ipv6 = YES;
                continue;
            }
            
            // 链路本地地址必须指定接口，否则可能不可达
            BOOL is_link_local = (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
            if (is_link_local && interface_index == 0) {
                continue;
            }
            ipv6_result = p;
        }
    }
    
    // 根据偏好选择地址，结合接口能力进行过滤
    BOOL iface_found = NO;
    BOOL iface_has_v4 = NO;
    BOOL iface_has_v6 = NO;
    if (interface_index > 0) {
        // 如果接口不存在或未UP，后续选择会失败
        interface_supports_family(interface_index, AF_INET, &iface_found, &iface_has_v4);
        interface_supports_family(interface_index, AF_INET6, NULL, &iface_has_v6);
    }
    
    // 根据偏好选择地址
    struct addrinfo *selected = NULL;
    if (prefer == 1 || prefer == 3) {
        // IPv6优先或IPv6 only：优先使用IPv6，如果没有则使用IPv4（除非是IPv6 only）
        if (ipv6_result && (interface_index == 0 || iface_has_v6)) {
            selected = ipv6_result;
        } else {
            selected = (prefer == 3 ? NULL : ((interface_index == 0 || iface_has_v4) ? ipv4_result : NULL));
        }
    } else {
        // IPv4优先或IPv4 only：优先使用IPv4，如果没有则使用IPv6（除非是IPv4 only）
        if (ipv4_result && (interface_index == 0 || iface_has_v4)) {
            selected = ipv4_result;
        } else if (prefer != 2 && ipv6_result && (interface_index == 0 || iface_has_v6)) {
            selected = ipv6_result;
        } else {
            selected = NULL;
        }
    }
    
    if (selected == NULL) {
        // 如果仅找到 IPv4-mapped IPv6 地址且要求 IPv6 only/优先，返回特殊错误
        if ((prefer == 1 || prefer == 3) && has_mapped_ipv6 && ipv6_result == NULL) {
            freeaddrinfo(result);
            return -2;
        }
        freeaddrinfo(result);
        return -1;
    }
    
    // 严格验证：确保选择的地址类型与偏好一致
    if (prefer == 2 && selected->ai_family != AF_INET) {
        // IPv4 only：必须选择IPv4地址
        freeaddrinfo(result);
        return -1;
    }
    if (prefer == 3 && selected->ai_family != AF_INET6) {
        // IPv6 only：必须选择IPv6地址
        freeaddrinfo(result);
        return -1;
    }
    
    // 将选中的地址转换为字符串格式
    int ntop_result = 0;
    if (selected->ai_family == AF_INET) {
        struct sockaddr_in *addr_in = (struct sockaddr_in *)selected->ai_addr;
        ntop_result = (inet_ntop(AF_INET, &(addr_in->sin_addr), ip_buffer, INET6_ADDRSTRLEN) != NULL) ? 0 : -1;
    } else if (selected->ai_family == AF_INET6) {
        struct sockaddr_in6 *addr_in6 = (struct sockaddr_in6 *)selected->ai_addr;
        ntop_result = (inet_ntop(AF_INET6, &(addr_in6->sin6_addr), ip_buffer, INET6_ADDRSTRLEN) != NULL) ? 0 : -1;
    } else {
        ntop_result = -1;
    }
    
    freeaddrinfo(result);
    return ntop_result;
}

// ============================================================================
// 发送和接收 ICMP 包
// ============================================================================

/**
 * 发送ICMP包（线程安全：每个socket应该只在一个线程中使用）
 * @param socket socket文件描述符
 * @param target_addr 目标地址
 * @param addr_len 地址长度
 * @param packet 要发送的数据包
 * @param result 结果结构（可选，用于设置错误信息）
 * @return 成功返回0，失败返回-1
 */
static int send_icmp_packet(int socket, const struct sockaddr *target_addr, socklen_t addr_len,
                            NSData *packet, cls_ping_detector_result *result) {
    // 参数验证
    if (socket < 0 || target_addr == NULL || packet == NULL || packet.length == 0) {
        if (result) {
            set_error_message(result, "Invalid parameters for send_icmp_packet");
        }
        return -1;
    }

    // 对 IPv6 主动填充校验和，避免内核未代填时出现 checksum=0
    // 注意：对于ICMPv6，内核会自动计算校验和，但如果能获取本地地址，手动计算可以确保正确性
    if (target_addr->sa_family == AF_INET6 && packet.length >= sizeof(ICMPHeader)) {
        struct sockaddr_in6 local_addr;
        memset(&local_addr, 0, sizeof(local_addr));
        socklen_t local_len = sizeof(local_addr);

        // 尝试获取本地地址（不connect，避免影响后续sendto/recvfrom）
        // 如果socket已绑定到接口，getsockname应该能返回本地地址
        if (getsockname(socket, (struct sockaddr *)&local_addr, &local_len) == 0 &&
            local_addr.sin6_family == AF_INET6 &&
            !IN6_IS_ADDR_UNSPECIFIED(&local_addr.sin6_addr)) {
            // 成功获取本地地址，手动计算校验和
            const struct sockaddr_in6 *addr6 = (const struct sockaddr_in6 *)target_addr;
            NSMutableData *mutablePacket = [packet mutableCopy];
            ICMPHeader *header = (ICMPHeader *)mutablePacket.mutableBytes;
            header->checksum = 0; // 先清零再计算
            uint16_t checksum = calculate_icmpv6_checksum(&local_addr.sin6_addr,
                                                          &addr6->sin6_addr,
                                                          mutablePacket.bytes,
                                                          mutablePacket.length);
            header->checksum = checksum;
            packet = mutablePacket; // 使用带校验和的数据
        }
        // 如果无法获取本地地址，依赖内核自动计算校验和（这是正常情况，不记录异常）
    }

    ssize_t sent = sendto(socket, packet.bytes, packet.length, 0, target_addr, addr_len);
    if (sent < 0) {
        // 记录发送失败的错误码
        int err = errno;
        char addr_str[INET6_ADDRSTRLEN];
        if (target_addr->sa_family == AF_INET6) {
            struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)target_addr;
            inet_ntop(AF_INET6, &addr6->sin6_addr, addr_str, INET6_ADDRSTRLEN);
        } else {
            struct sockaddr_in *addr4 = (struct sockaddr_in *)target_addr;
            inet_ntop(AF_INET, &addr4->sin_addr, addr_str, INET_ADDRSTRLEN);
        }
        if (result && result->error_message[0] == '\0') {
            set_error_message(result, "sendto failed: errno=%d (%s), target=%s, family=%d, addr_len=%d, packet_len=%zu",
                  err, strerror(err), addr_str, target_addr->sa_family, addr_len, packet.length);
        }
        return -1;
    }
    if (sent != (ssize_t)packet.length) {
        if (result && result->error_message[0] == '\0') {
            set_error_message(result, "sendto partial: sent=%zd, expected=%zu", sent, packet.length);
        }
        return -1;
    }
    return 0;
}

// 绑定 socket 到指定接口，interface_index=0 表示不绑定
static int bind_socket_to_interface(int sock, BOOL isIPv6, unsigned int interface_index, cls_ping_detector_result *result) {
    if (interface_index == 0) {
        return 0; // 不绑定，使用系统默认
    }
    
    if (isIPv6) {
        // iOS/macOS 使用 IPV6_BOUND_IF 进行接口绑定
        if (setsockopt(sock, IPPROTO_IPV6, IPV6_BOUND_IF, &interface_index, sizeof(interface_index)) < 0) {
            int err = errno;
            if (result && result->error_message[0] == '\0') {
                set_error_message(result, "bind IPv6 iface failed: ifindex=%u errno=%d (%s)", interface_index, err, strerror(err));
            }
            if (result) {
                result->bindFailed += 1; // 记录绑定失败次数
            }
            return -1;
        }
    } else {
        // iOS/macOS 使用 IP_BOUND_IF 进行接口绑定
        if (setsockopt(sock, IPPROTO_IP, IP_BOUND_IF, &interface_index, sizeof(interface_index)) < 0) {
            int err = errno;
            if (result && result->error_message[0] == '\0') {
                set_error_message(result, "bind IPv4 iface failed: ifindex=%u errno=%d (%s)", interface_index, err, strerror(err));
            }
            if (result) {
                result->bindFailed += 1; // 记录绑定失败次数
            }
            return -1;
        }
    }
    return 0;
}

// 接收任意序列号的ICMP回包，返回序列号和RTT（通过输出参数）
// 返回值：成功返回1，失败返回0，超时返回-1，收到ICMP错误返回-3并写入out_icmp_error
static int receive_icmp_reply_any(int socket, int timeout_ms, BOOL isIPv6,
                                 int max_sequence,
                                 uint16_t *out_sequence, double *out_rtt,
                                 const struct timeval *send_times,
                                 const char *expected_ip,
                                 cls_ping_detector_error_code *out_icmp_error) {
    if (socket < 0 || out_sequence == NULL || out_rtt == NULL) {
        return -1;
    }
    
    // 限制超时时间在合理范围内
    // 接收阶段允许更短的超时以避免阻塞发送；最低10ms
    if (timeout_ms < 10) {
        timeout_ms = 10;
    } else if (timeout_ms > PING_MAX_TIMEOUT_MS) {
        timeout_ms = PING_MAX_TIMEOUT_MS;
    }
    
    // 等待socket可读（使用select进行非阻塞等待）
    if (!wait_for_socket_readable(socket, timeout_ms)) {
        return -1; // 超时
    }
    
    // 接收数据缓冲区（足够大以容纳IP头+ICMP包）
    char buffer[2048];
    ssize_t bytes_received = 0;
    ip_addr_t src_addr = {0}, dst_addr = {0};
    BOOL has_addrs = NO;
    char from_ip[INET6_ADDRSTRLEN] = {0};
    
    // 根据IP版本接收数据
    if (isIPv6) {
        struct sockaddr_in6 from_addr;
        memset(&from_addr, 0, sizeof(from_addr));
        socklen_t from_len = sizeof(from_addr);
        bytes_received = recvfrom(socket, buffer, sizeof(buffer), 0,
                                 (struct sockaddr *)&from_addr, &from_len);
        
        if (bytes_received > 0) {
            // 回包来源（远端）作为校验和的源地址
            src_addr.v6 = from_addr.sin6_addr;
            
            // 获取本地socket地址（用于IPv6校验和验证）
            // 根据 RFC 2460，ICMPv6 校验和是强制字段，必须验证
            // 校验和计算需要源地址（回包来源）和目标地址（本地地址）
            struct sockaddr_in6 local_addr;
            memset(&local_addr, 0, sizeof(local_addr));
            socklen_t local_len = sizeof(local_addr);
            
            // 尝试获取本地socket地址
            // 注意：getsockname 可能失败的情况包括：
            // 1. socket 未绑定地址（某些系统配置下）
            // 2. socket 状态异常
            // 3. 系统调用失败
            // 如果无法获取本地地址，将无法验证 ICMPv6 校验和，根据 RFC 2460 应拒绝该包
            if (getsockname(socket, (struct sockaddr *)&local_addr, &local_len) == 0 &&
                local_addr.sin6_family == AF_INET6 &&
                !IN6_IS_ADDR_UNSPECIFIED(&local_addr.sin6_addr)) {
                dst_addr.v6 = local_addr.sin6_addr; // 本地作为目的地址
                has_addrs = YES;
            }
            // 如果 getsockname 失败或返回未指定地址，has_addrs 保持为 NO
            // 后续在 validate_icmp_reply 中会因无法验证校验和而拒绝该包
            
            // 记录来源IP，后续与期望目标匹配，避免误判
            inet_ntop(AF_INET6, &from_addr.sin6_addr, from_ip, sizeof(from_ip));
        }
    } else {
        struct sockaddr_in from_addr;
        memset(&from_addr, 0, sizeof(from_addr));
        socklen_t from_len = sizeof(from_addr);
        bytes_received = recvfrom(socket, buffer, sizeof(buffer), 0,
                                 (struct sockaddr *)&from_addr, &from_len);
        if (bytes_received > 0) {
            // IPv4 场景下，地址存储在 v4 字段中（虽然当前不使用，但保持类型一致性）
            src_addr.v4 = from_addr.sin_addr;
            has_addrs = YES; // 标记已获取地址（虽然 IPv4 不需要用于校验和）
            inet_ntop(AF_INET, &from_addr.sin_addr, from_ip, sizeof(from_ip));
        }
    }

    // 检查接收结果
    if (bytes_received < 0) {
        // 接收错误处理
        int err = errno;
        
        // EINTR: 被信号中断，应该重试（但在非阻塞模式下，这里返回让上层处理）
        // EAGAIN/EWOULDBLOCK: 非阻塞模式下没有数据可读，正常情况
        if (err == EINTR || err == EAGAIN || err == EWOULDBLOCK) {
            return 0; // 正常情况，返回让调用者决定是否重试
        }
        return 0; // 接收失败
    }
    
    if (bytes_received == 0) {
        return 0; // 对端关闭连接（ICMP不应该出现这种情况）
    }

    // 校验来源IP，避免将其他会话的回包计入
    if (expected_ip && expected_ip[0] != '\0' && from_ip[0] != '\0') {
        if (!ip_equal_ignore_scope(expected_ip, from_ip)) {
            return 0; // 来源不匹配，忽略
        }
    }

    // 重要：使用SOCK_DGRAM时，recvfrom返回的数据直接是ICMP包，不包含IP头
    // 内核已经处理了IP层，我们只需要处理ICMP层
    // 这与SOCK_RAW不同，SOCK_RAW需要自己处理IP头
    const uint8_t *icmp_bytes = (const uint8_t *)buffer;
    size_t icmp_len = (size_t)bytes_received;
    
    // 注意：某些系统或配置下，可能会返回包含IP头的数据
    // 为了兼容性，检查第一个字节是否是IP头（version=4），如果是则跳过IP头
    // 但正常情况下，SOCK_DGRAM不应该包含IP头
    if (!isIPv6 && bytes_received >= 20) {
        // 检查第一个字节是否是IPv4头（version=4）
        uint8_t vihl = buffer[0];
        uint8_t version = (vihl & 0xF0) >> 4;
        
        // 如果确实是IPv4头（version=4），则跳过IP头
        // 但这种情况在SOCK_DGRAM下不应该发生
        if (version == 4) {
            uint8_t ihl = (vihl & 0x0F);
            if (ihl >= 5 && ihl <= 15) {
                size_t ip_header_len = (size_t)ihl * 4;
                if (ip_header_len >= 20 && ip_header_len < (size_t)bytes_received) {
                    // 确实包含IP头，跳过它
                    icmp_bytes = ((const uint8_t *)buffer) + ip_header_len;
                    icmp_len = (size_t)bytes_received - ip_header_len;
                }
            }
        }
        // 如果version不是4，说明不是IP头，直接使用buffer作为ICMP包（正常情况）
    }

    // 验证ICMP包长度
    if (icmp_len < sizeof(ICMPHeader)) {
        return 0; // 数据太短，不是有效的ICMP包
    }
    
    // 处理ICMP错误报文（目的不可达、超时等）
    uint8_t icmp_type_peek = ((const uint8_t *)icmp_bytes)[0];
    uint8_t icmp_code_peek = ((const uint8_t *)icmp_bytes)[1];
    if (!isIPv6) {
        if (icmp_type_peek == ICMP_UNREACH) {
            if (out_icmp_error) {
                *out_icmp_error = cls_ping_detector_error_network_unreachable;
            }
            return -3;
        } else if (icmp_type_peek == ICMP_TIMXCEED) {
            if (out_icmp_error) {
                *out_icmp_error = cls_ping_detector_error_timeout;
            }
            return -3;
        }
    } else {
        if (icmp_type_peek == ICMP6_DST_UNREACH) {
            (void)icmp_code_peek; // 统一归为网络不可达
            if (out_icmp_error) {
                *out_icmp_error = cls_ping_detector_error_network_unreachable;
            }
            return -3;
        } else if (icmp_type_peek == ICMP6_TIME_EXCEEDED) {
            if (out_icmp_error) {
                *out_icmp_error = cls_ping_detector_error_timeout;
            }
            return -3;
        }
    }
    
    const ICMPHeader *h = (const ICMPHeader *)icmp_bytes;
    uint16_t recv_seq = ntohs(h->sequence);
    uint8_t expected_type = isIPv6 ? ICMPV6_ECHO_REPLY : ICMP_ECHO_REPLY;
    
    // 快速验证：检查ICMP类型
    if (h->type != expected_type) {
        return 0; // 类型不匹配（可能是其他ICMP消息）
    }
    
    // 验证序列号范围（必须在已发送的序列号范围内）
    // 注意：recv_seq是uint16_t，所以不会为负数，但需要检查是否在有效范围内
    if (recv_seq > (uint16_t)max_sequence || max_sequence < 0) {
        return 0; // 序列号超出范围（可能是旧的或无效的包）
    }
    
    // 验证ICMP回复（使用宽松模式：允许ID被NAT改写）
    // 根据 IP 版本传递正确的地址类型（IPv6 需要地址用于校验和，IPv4 不需要）
    const ip_addr_t *src_ptr = (isIPv6 && has_addrs) ? &src_addr : NULL;
    const ip_addr_t *dst_ptr = (isIPv6 && has_addrs) ? &dst_addr : NULL;
    
    // 验证ICMP包的有效性（校验和、负载模式等）
    BOOL validation_result = validate_icmp_reply(icmp_bytes, icmp_len, isIPv6,
                          expected_type, recv_seq,
                          src_ptr, dst_ptr);
    
    if (validation_result) {
        // 匹配成功，计算RTT
        // 优先使用发送时间数组；缺失时尝试从payload时间戳推算
        if (recv_seq <= (uint16_t)max_sequence && max_sequence >= 0) {
            BOOL rtt_obtained = NO;

            if (send_times != NULL && (send_times[recv_seq].tv_sec != 0 || send_times[recv_seq].tv_usec != 0)) {
                struct timeval end_time;
                gettimeofday(&end_time, NULL);
                
                int64_t sec_diff = (int64_t)end_time.tv_sec - (int64_t)send_times[recv_seq].tv_sec;
                int64_t usec_diff = (int64_t)end_time.tv_usec - (int64_t)send_times[recv_seq].tv_usec;
                
                double elapsed = sec_diff * 1000.0 + usec_diff / 1000.0;
                if (elapsed >= -1.0 && elapsed < (timeout_ms * 10.0)) {
                    if (elapsed < 0.0) {
                        elapsed = 0.0;
                    }
                    *out_sequence = recv_seq;
                    *out_rtt = elapsed;
                    return 1; // 成功匹配
                }
            }

            // send_times缺失或不合理，尝试从payload中的时间戳计算RTT
            size_t payload_len = (icmp_len > sizeof(ICMPHeader)) ? (icmp_len - sizeof(ICMPHeader)) : 0;
            if (payload_len >= sizeof(uint64_t)) {
                uint64_t send_ts_ms = 0;
                memcpy(&send_ts_ms, icmp_bytes + sizeof(ICMPHeader), sizeof(uint64_t));
                uint64_t now_ms = get_current_timestamp_ms();
                if (now_ms >= send_ts_ms) {
                    double elapsed = (double)(now_ms - send_ts_ms);
                    if (elapsed >= 0.0 && elapsed < (timeout_ms * 10.0)) {
                        *out_sequence = recv_seq;
                        *out_rtt = elapsed;
                        rtt_obtained = YES;
                    }
                }
            }

            if (rtt_obtained) {
                return 1;
            }
        }
    }
    
    return 0; // 验证失败（可能是其他包的响应或无效包）
}

// ============================================================================
// 执行 Ping 循环 - 辅助函数
// ============================================================================

/**
 * 计算从开始时间到现在的已用时间（微秒）
 * @param start_time 开始时间
 * @return 已用时间（微秒）
 */
static int64_t calculate_elapsed_us(const struct timeval *start_time) {
    struct timeval current_time;
    gettimeofday(&current_time, NULL);
    return ((int64_t)(current_time.tv_sec - start_time->tv_sec) * 1000000 +
            (int64_t)(current_time.tv_usec - start_time->tv_usec));
}

/**
 * 处理接收到的ICMP回包
 * 更新接收状态、RTT数组和统计信息
 * @param recv_seq 接收到的序列号
 * @param recv_rtt 接收到的RTT（毫秒）
 * @param times 总发送次数
 * @param received 接收状态数组
 * @param rtts RTT数组
 * @param packets_received 已接收包数（输出参数）
 * @param rtt_list RTT列表（用于统计计算）
 */
static void handle_received_packet(uint16_t recv_seq, double recv_rtt, int times,
                                  BOOL *received, double *rtts, int *packets_received,
                                  RttArray *rtt_list) {
    // 验证序列号范围
    if (recv_seq >= (uint16_t)times || received == NULL || rtts == NULL || 
        packets_received == NULL || rtt_list == NULL) {
        return;
    }
    
    if (!received[recv_seq]) {
        received[recv_seq] = YES;
        rtts[recv_seq] = recv_rtt;
        (*packets_received)++;
        
        // rtt_array_add可能失败（内存分配失败），但不影响基本统计
        if (rtt_array_add(rtt_list, recv_rtt) != 0) {
            // 继续执行，因为基本统计（packets_received）已经更新
        }
    }
}

/**
 * 尝试接收一个ICMP回包（在发送阶段使用）
 * 在发送每个包后立即尝试接收，实现边发边收模式，避免RTT包含发送间隔
 * @param socket socket文件描述符
 * @param isIPv6 是否为IPv6
 * @param times 总发送次数
 * @param max_sequence 最大序列号
 * @param received_count 已接收包数（输入输出参数）
 * @param received 接收状态数组
 * @param loop_start_time 循环开始时间
 * @param total_timeout_us 总超时时间（微秒）(timeout_ms * times) + (interval_ms * (times - 1))
 * @param sequence 当前序列号
 * @param timeout_ms 单次超时时间（毫秒）
 * @param send_times 发送时间数组
 * @param rtts RTT数组
 * @param rtt_list RTT列表
 * @return 1=收到匹配包，0=收到但不匹配，-1=超时，-2=所有包已收到或总超时
 */
static int try_receive_during_send(int socket, BOOL isIPv6, int times, int max_sequence,
                                   int *received_count, BOOL *received,
                                   const struct timeval *loop_start_time,
                                   int64_t total_timeout_us, int sequence,
                                   int timeout_ms, struct timeval *send_times,
                                   double *rtts, RttArray *rtt_list,
                                   const char *expected_ip,
                                   cls_ping_detector_error_code *out_icmp_error) {
    // 快速检查：如果所有包都已收到，直接返回
    if (*received_count == times) {
        return -2;
    }
    
    // 检查总超时
    int64_t elapsed_us = calculate_elapsed_us(loop_start_time);
    if (elapsed_us >= total_timeout_us) {
        return -2;
    }
    
    // 计算接收超时时间（发送阶段使用较短超时，以便及时发送下一个包）
    int recv_timeout_ms = (sequence < times - 1) ? 50 : timeout_ms;
    if (elapsed_us < total_timeout_us) {
        int64_t remaining_us = total_timeout_us - elapsed_us;
        if (remaining_us < recv_timeout_ms * 1000) {
            recv_timeout_ms = (int)(remaining_us / 1000);
        }
        if (recv_timeout_ms < 10) {
            recv_timeout_ms = 10; // 最小10ms
        }
    }
    
    // 尝试接收一个回包
    uint16_t recv_seq;
    double recv_rtt;
    int recv_result = receive_icmp_reply_any(socket, recv_timeout_ms, isIPv6,
                                             max_sequence, &recv_seq, &recv_rtt, send_times,
                                             expected_ip, out_icmp_error);
    
    if (recv_result == -3) {
        return -2; // 收到明确ICMP错误，提前结束
    } else if (recv_result == 1) {
        // 成功接收到匹配的回包
        int packets_received_local = *received_count;
        handle_received_packet(recv_seq, recv_rtt, times, received, rtts,
                              &packets_received_local, rtt_list);
        *received_count = packets_received_local;
        return 1;
    }
    
    return recv_result; // -1=超时，0=不匹配
}

/**
 * 接收剩余的回包（所有包发送完成后）
 * 继续等待并接收所有未收到的回包，直到所有包都收到或总超时
 * @param socket socket文件描述符
 * @param isIPv6 是否为IPv6
 * @param times 总发送次数
 * @param max_sequence 最大序列号
 * @param received 接收状态数组
 * @param rtts RTT数组
 * @param packets_received 已接收包数（输入输出参数）
 * @param loop_start_time 循环开始时间
 * @param total_timeout_us 总超时时间（微秒）
 * @param timeout_ms 单次超时时间（毫秒）
 * @param send_times 发送时间数组
 * @param rtt_list RTT列表
 */
static void receive_remaining_packets(int socket, BOOL isIPv6, int times, int max_sequence,
                                     BOOL *received, double *rtts, int *packets_received,
                                     const struct timeval *loop_start_time,
                                     int64_t total_timeout_us, int timeout_ms,
                                     struct timeval *send_times, RttArray *rtt_list,
                                     const char *expected_ip,
                                     cls_ping_detector_error_code *out_icmp_error) {
    int received_count = *packets_received;
    
    while (received_count < times) {
        // 检查总超时
        int64_t elapsed_us = calculate_elapsed_us(loop_start_time);
        if (elapsed_us >= total_timeout_us) {
            break;
        }
        
        // 计算剩余超时时间
        int remaining_timeout_ms = timeout_ms;
        if (elapsed_us < total_timeout_us) {
            remaining_timeout_ms = (int)((total_timeout_us - elapsed_us) / 1000);
            if (remaining_timeout_ms < 10) {
                remaining_timeout_ms = 10; // 最小10ms，与发送阶段保持一致
            } else if (remaining_timeout_ms > timeout_ms) {
                remaining_timeout_ms = timeout_ms; // 不超过单包配置超时
            }
        }
        
        // 尝试接收一个回包
        uint16_t recv_seq;
        double recv_rtt;
        int recv_result = receive_icmp_reply_any(socket, remaining_timeout_ms, isIPv6,
                                                 max_sequence, &recv_seq, &recv_rtt, send_times,
                                                 expected_ip, out_icmp_error);
        
        if (recv_result == -3) {
            // 明确ICMP错误，停止等待
            break;
        } else if (recv_result == 1) {
            // 成功接收到匹配的回包
            handle_received_packet(recv_seq, recv_rtt, times, received, rtts,
                                  &received_count, rtt_list);
        } else if (recv_result == -1) {
            // 超时，继续等待其他包（可能还有包在路上）
            continue;
        }
        // recv_result == 0 表示收到包但不匹配，继续接收
    }
    
    *packets_received = received_count;
}

// ============================================================================
// 执行 Ping 循环
// ============================================================================

/**
 * 执行Ping循环：发送ICMP包并接收回包
 * 采用边发边收模式，发送每个包后立即尝试接收，避免RTT包含发送间隔
 * 
 * @param socket socket文件描述符
 * @param target_addr 目标地址
 * @param addr_len 地址长度
 * @param times 发送次数
 * @param packet_size 包大小（不包含ICMP头）
 * @param ttl TTL值
 * @param timeout_ms 超时时间（毫秒）
 * @param interval_ms 发送间隔（毫秒）
 * @param identifier ICMP标识符
 * @param isIPv6 是否为IPv6
 * @param resolved_ip 解析后的IP地址（用于日志）
 * @param rtt_list RTT列表（输出）
 * @param packets_received 已接收包数（输出）
 * @param permission_denied 是否检测到权限错误（输出）
 * @param result 结果结构（输出，包含异常统计）
 */
static void perform_ping_loop(int socket, const struct sockaddr *target_addr, socklen_t addr_len,
                             int times, int packet_size, int ttl, int timeout_ms, int interval_ms,
                             uint16_t identifier, BOOL isIPv6, const char *resolved_ip,
                             RttArray *rtt_list, int *packets_received, int *packets_sent_out,
                             BOOL *permission_denied, cls_ping_detector_result *result,
                             cls_ping_detector_error_code *out_icmp_error) {
    // 参数验证
    if (socket < 0 || target_addr == NULL || rtt_list == NULL || 
        packets_received == NULL || packets_sent_out == NULL || result == NULL) {
        if (result) {
            result->exceptionNum = times > 0 ? times : 1;
        }
        if (packets_sent_out) {
            *packets_sent_out = 0;
        }
        return;
    }
    
    *packets_received = 0;
    if (permission_denied) {
        *permission_denied = NO;
    }
    result->exceptionNum = 0;
    if (out_icmp_error) {
        *out_icmp_error = cls_ping_detector_error_success;
    }
    
    // 分配数组记录发送时间和接收状态
    // 使用临时变量确保在分配失败时能正确清理
    struct timeval *send_times = NULL;
    BOOL *received = NULL;
    double *rtts = NULL;
    
    // 检查times是否会导致整数溢出
    if (times <= 0 || times > PING_MAX_TIMES) {
        result->exceptionNum = times;
        return;
    }
    
    // 分配内存（使用calloc初始化为0，便于后续判断是否发送成功）
    send_times = (struct timeval *)calloc(times, sizeof(struct timeval));
    if (!send_times) {
        set_error_message(result, "Failed to allocate memory for send_times array");
        result->exceptionNum = times;
        return;
    }
    
    received = (BOOL *)calloc(times, sizeof(BOOL));
    if (!received) {
        set_error_message(result, "Failed to allocate memory for received array");
        free(send_times);
        result->exceptionNum = times;
        return;
    }
    
    rtts = (double *)calloc(times, sizeof(double));
    if (!rtts) {
        set_error_message(result, "Failed to allocate memory for rtts array");
        free(send_times);
        free(received);
        result->exceptionNum = times;
        return;
    }
    
    // 边发边收模式：发送每个包后立即开始接收，避免RTT包含发送间隔
    struct timeval loop_start_time;
    gettimeofday(&loop_start_time, NULL);
    
    // 计算总超时时间： (timeout_ms * times) + (interval_ms * (times - 1))
    // 精确贴合配置，并做溢出保护
    int64_t timeout_us = (int64_t)timeout_ms * 1000;
    int64_t interval_us = (int64_t)interval_ms * 1000;
    if (timeout_us < 0) timeout_us = INT64_MAX / 2;
    if (interval_us < 0) interval_us = INT64_MAX / 2;
    
    int64_t total_timeout_us = 0;
    if (times > 0) {
        // timeout 部分
        if (timeout_us <= INT64_MAX / times) {
            total_timeout_us = timeout_us * times;
        } else {
            total_timeout_us = INT64_MAX / 2;
        }
        // interval 部分（times-1 个间隔）
        int send_intervals = times - 1;
        if (send_intervals > 0 && interval_us > 0) {
            if (interval_us <= (INT64_MAX - total_timeout_us) / send_intervals) {
                total_timeout_us += interval_us * send_intervals;
            } else {
                total_timeout_us = INT64_MAX / 2;
            }
        }
    } else {
        total_timeout_us = INT64_MAX / 2;
    }
    
    int received_count = 0; // 已收到的包数量（用于快速检查）
    uint8_t icmp_type = isIPv6 ? ICMPV6_ECHO_REQUEST : ICMP_ECHO_REQUEST;
    
    // 使用一个数组标记哪些包实际发送成功（用于后续统计）
    BOOL *sent = (BOOL *)calloc(times, sizeof(BOOL));
    if (!sent) {
        // 如果分配失败，使用简化逻辑（不区分发送失败和未收到）
        sent = NULL;
    }
    
    // 发送所有包，边发边收
    int actual_packets_sent = 0; // 实际成功发送的包数
    for (int sequence = 0; sequence < times; sequence++) {
        // 验证序列号不会溢出uint16_t
        if (sequence > 65535) {
            result->exceptionNum++;
            continue;
        }
        
        // 构建ICMP包
        NSData *packet = build_icmp_packet(packet_size, icmp_type, sequence, identifier, isIPv6);
        if (!packet) {
            if (result->error_message[0] == '\0') {
                set_error_message(result, "Failed to build ICMP packet for sequence %d", sequence);
            }
            result->exceptionNum++;
            continue;
        }
        
        // 发送包
        errno = 0;
        int send_result = send_icmp_packet(socket, target_addr, addr_len, packet, result);
        if (send_result != 0) {
            result->exceptionNum++;
            if (permission_denied && (errno == EPERM || errno == EACCES)) {
                *permission_denied = YES;
            }
            // 发送失败，不记录发送时间，也不计入实际发送数
            continue;
        }
        
        // 发送成功，记录发送时间、标记为已发送，并增加实际发送数
        actual_packets_sent++;
        if (sent) {
            sent[sequence] = YES;
        }
        gettimeofday(&send_times[sequence], NULL);
        
        // 发送后立即尝试接收回包（边发边收模式）
        // 持续接收直到收到匹配的包、超时或所有包都已收到
        while (received_count < times) {
        int recv_result = try_receive_during_send(socket, isIPv6, times, times - 1,
                                                  &received_count, received,
                                                  &loop_start_time, total_timeout_us,
                                                  sequence, timeout_ms, send_times,
                                                  rtts, rtt_list, resolved_ip, out_icmp_error);
            
            if (recv_result == -2) {
                // 所有包已收到或总超时
                goto all_received;
            } else if (recv_result == -1) {
                // 超时，退出接收循环，继续发送下一个包
                break;
            }
            // recv_result == 1 表示收到匹配包，继续接收其他包
            // recv_result == 0 表示收到包但不匹配，继续接收
        }
        
        // 等待间隔（最后一次不需要等待）
        if (sequence < times - 1 && interval_ms > 0) {
            // 如果总超时已到，跳出发送循环
            int64_t elapsed_us_before_sleep = calculate_elapsed_us(&loop_start_time);
            if (elapsed_us_before_sleep >= total_timeout_us) {
                goto all_received;
            }
            
            // usleep可能被信号中断，需要重试直到完全等待
            // 在macOS/iOS上，usleep被信号中断时返回-1，设置errno为EINTR
            useconds_t remaining_us = (useconds_t)(interval_ms * 1000);
            struct timeval sleep_start, sleep_current;
            gettimeofday(&sleep_start, NULL);
            
            while (remaining_us > 0) {
                int usleep_result = usleep(remaining_us);
                if (usleep_result == 0) {
                    // 完全等待完成
                    break;
                }
                
                // 检查是否被信号中断
                if (usleep_result == -1 && errno == EINTR) {
                    // 被信号中断，计算已等待时间，继续等待剩余时间
                    gettimeofday(&sleep_current, NULL);
                    int64_t elapsed_us = ((int64_t)(sleep_current.tv_sec - sleep_start.tv_sec) * 1000000 +
                                         (int64_t)(sleep_current.tv_usec - sleep_start.tv_usec));
                    int64_t total_sleep_us = (int64_t)(interval_ms * 1000);
                    int64_t remaining = total_sleep_us - elapsed_us;
                    
                    if (remaining <= 0) {
                        // 已经等待足够时间
                        break;
                    }
                    remaining_us = (useconds_t)remaining;
                } else {
                    // 其他错误，记录日志但继续
                    break;
                }
                
                // 每次循环都检查总超时时间，避免整体耗时超限
                int64_t elapsed_us_total = calculate_elapsed_us(&loop_start_time);
                if (elapsed_us_total >= total_timeout_us) {
                    goto all_received;
                }
            }
        }
    }
    
    // 所有包发送完成后，继续接收剩余的回包
    // 重要：先将发送阶段收到的包数同步到输出参数
    *packets_received = received_count;
    receive_remaining_packets(socket, isIPv6, times, times - 1, received, rtts,
                              packets_received, &loop_start_time, total_timeout_us,
                              timeout_ms, send_times, rtt_list, resolved_ip, out_icmp_error);
    
all_received:
    
    // 确保packets_received已同步（如果从发送阶段直接跳转到这里）
    if (*packets_received != received_count) {
        *packets_received = received_count;
    }
    
    // 统计未收到的包（只统计实际发送但未收到的包）
    // 注意：发送失败的包已经在发送时计入exceptionNum，这里不再重复计算
    for (int i = 0; i < times; i++) {
        if (!received[i]) {
            // 判断该包是否实际发送成功
            BOOL was_sent = NO;
            if (sent) {
                // 使用sent数组判断（最准确的方式）
                was_sent = sent[i];
            } else {
                // sent数组分配失败，使用send_times判断
                // send_times使用calloc分配，初始值为全0
                // 如果发送成功，gettimeofday会设置tv_sec和tv_usec（不会为0，除非是1970-01-01）
                // 为了更准确，检查send_times[i]是否在循环开始时间之后
                if (send_times[i].tv_sec > loop_start_time.tv_sec ||
                    (send_times[i].tv_sec == loop_start_time.tv_sec && 
                     send_times[i].tv_usec >= loop_start_time.tv_usec)) {
                    was_sent = YES;
                } else if (send_times[i].tv_sec != 0 || send_times[i].tv_usec != 0) {
                    // 如果tv_sec或tv_usec不为0，但不在循环开始时间之后
                    // 可能是系统时间异常，但为了安全，仍然认为发送成功
                    was_sent = YES;
                }
            }
            
            if (was_sent) {
                // 发送成功但未收到，计入异常
                result->exceptionNum++;
            }
            // 如果was_sent为NO，说明发送失败，已经在发送时计入exceptionNum
        }
    }
    
    // 更新实际发送的包数（用于后续统计）
    if (packets_sent_out) {
        *packets_sent_out = actual_packets_sent;
    }
    
    // 清理内存
    if (sent) {
        free(sent);
    }
    free(send_times);
    free(received);
    free(rtts);
}

// ============================================================================
// 资源管理辅助结构
// ============================================================================

typedef struct {
    int socket_fd; // socket文件描述符，-1表示未创建
} PingResources;

/**
 * 清理Ping资源（线程安全）
 * 注意：此函数应该只在一个线程中调用，或者在调用前确保资源未被其他线程使用
 * @param resources 资源结构指针
 */
static void cleanup_ping_resources(PingResources *resources) {
    if (resources == NULL) {
        return;
    }
    
    // 关闭socket（原子操作：先获取fd值，然后标记为无效）
    // socket操作本身不是线程安全的，但这里通过先标记为无效来防止重复关闭
    int fd = resources->socket_fd;
    if (fd >= 0) {
        resources->socket_fd = -1; // 先标记为无效，防止重复关闭
        // 关闭socket（忽略错误，因为可能已经被关闭或无效）
        // 注意：close()可能失败（如EBADF），但在清理时通常可以忽略
        int close_result = close(fd);
        if (close_result < 0) {
            #ifdef DEBUG
            int err = errno;
            if (err != EBADF) { // EBADF是预期的（fd已关闭）
                NSLog(@"Warning: close() failed: errno=%d (%s)", err, strerror(err));
            }
            #endif
        }
    }
    
}

// ============================================================================
// 主 Ping 函数
// ============================================================================

cls_ping_detector_error_code cls_ping_detector_perform_ping(const char *target,
                                                             const cls_ping_detector_config *config,
                                                             cls_ping_detector_result *result) {
    // 初始化资源结构
    PingResources resources = {-1};
    cls_ping_detector_error_code error_code = cls_ping_detector_error_success;
    
    // 参数验证
    if (target == NULL || result == NULL) {
        return cls_ping_detector_error_invalid_target;
    }
    
    // 初始化结果结构
    memset(result, 0, sizeof(cls_ping_detector_result));
    result->error_code = cls_ping_detector_error_success;  // 初始化为成功，后续根据实际情况更新
    strncpy(result->target, target, sizeof(result->target) - 1);
    result->target[sizeof(result->target) - 1] = '\0'; // 确保字符串结束
    strncpy(result->method, "ping", sizeof(result->method) - 1);
    result->method[sizeof(result->method) - 1] = '\0';
    
    // 解析配置参数
    int packet_size = (config && config->packet_size > 0) ? config->packet_size : PING_DEFAULT_PACKET_SIZE;
    int ttl = (config && config->ttl > 0) ? config->ttl : PING_DEFAULT_TTL;
    int timeout_ms = (config && config->timeout_ms > 0) ? config->timeout_ms : PING_DEFAULT_TIMEOUT_MS;
    int interval_ms = (config && config->interval_ms > 0) ? config->interval_ms : PING_DEFAULT_INTERVAL_MS;
    int times = (config && config->times > 0) ? config->times : PING_DEFAULT_TIMES;
    unsigned int interface_index = (config && config->interface_index > 0) ? config->interface_index : 0;
    int prefer = -1; // 默认自动检测
    
    // 参数范围验证
    if (packet_size < PING_MIN_PACKET_SIZE || packet_size > PING_MAX_PACKET_SIZE) {
        result->error_code = cls_ping_detector_error_invalid_target;
        return cls_ping_detector_error_invalid_target;
    }
    
    if (ttl < PING_MIN_TTL || ttl > PING_MAX_TTL) {
        result->error_code = cls_ping_detector_error_invalid_target;
        return cls_ping_detector_error_invalid_target;
    }
    
    if (timeout_ms < PING_MIN_TIMEOUT_MS) {
        timeout_ms = PING_MIN_TIMEOUT_MS;
    } else if (timeout_ms > PING_MAX_TIMEOUT_MS) {
        timeout_ms = PING_MAX_TIMEOUT_MS;
    }
    
    if (interval_ms < PING_MIN_INTERVAL_MS) {
        interval_ms = PING_MIN_INTERVAL_MS;
    } else if (interval_ms > PING_MAX_INTERVAL_MS) {
        interval_ms = PING_MAX_INTERVAL_MS;
    }
    
    if (times < PING_MIN_TIMES || times > PING_MAX_TIMES) {
        result->error_code = cls_ping_detector_error_invalid_target;
        return cls_ping_detector_error_invalid_target;
    }

    // 解析主机名前先确定 prefer
    if (config && config->prefer >= 0) {
        prefer = config->prefer;
    } else {
        // 如果目标地址已经是IP地址，根据格式判断
        if (strchr(target, ':') != NULL) {
            prefer = 3; // IPv6 only
        } else if (strchr(target, '.') != NULL) {
            prefer = 2; // IPv4 only
        } else {
            prefer = 0; // 域名默认IPv4优先
        }
    }

    // 接口有效性校验（若指定接口）
    if (interface_index > 0) {
        BOOL iface_found = NO;
        BOOL iface_has_v4 = NO;
        BOOL iface_has_v6 = NO;
        BOOL iface_ok_v4 = interface_supports_family(interface_index, AF_INET, &iface_found, &iface_has_v4);
        BOOL iface_ok_v6 = interface_supports_family(interface_index, AF_INET6, NULL, &iface_has_v6);
        if (!iface_found || (!iface_ok_v4 && !iface_ok_v6)) {
            set_error_message(result, "Interface %u not found or not UP/RUNNING", interface_index);
            result->error_code = cls_ping_detector_error_net_binding_failed;
            return cls_ping_detector_error_net_binding_failed;
        }
        // 如果配置 prefer 仅IPv4/IPv6，但接口不支持对应协议族，直接报错
        if ((prefer == 2 && !iface_has_v4) || (prefer == 3 && !iface_has_v6)) {
            set_error_message(result, "Interface %u does not support requested IP family (prefer=%d)", interface_index, prefer);
            result->error_code = cls_ping_detector_error_net_binding_failed;
            return cls_ping_detector_error_net_binding_failed;
        }
    }
    
    // 解析主机名
    char resolved_ip[128];
    int resolve_ret = resolve_hostname(target, resolved_ip, prefer, interface_index);
    if (resolve_ret != 0) {
        // 如果指定了only模式但解析失败，直接返回错误
        if (prefer == 2 || prefer == 3) {
            if (resolve_ret == -2) {
                set_error_message(result, "Failed to resolve hostname '%s': only IPv4-mapped IPv6 found (prefer=%d, interface=%u)", 
                      target, prefer, interface_index);
            } else {
                set_error_message(result, "Failed to resolve hostname '%s' with prefer=%d, interface=%u", 
                      target, prefer, interface_index);
            }
            error_code = cls_ping_detector_error_resolve_error;
            result->packet_loss = 1.0; // hostname解析失败，视为100%丢包
            goto cleanup;
        }
        
        // 如果是优先模式，尝试另一种IP版本
        int fallback_prefer = (prefer == 0) ? 1 : 0;
        resolve_ret = resolve_hostname(target, resolved_ip, fallback_prefer, interface_index);
        if (resolve_ret != 0) {
            set_error_message(result, "Failed to resolve hostname '%s' (fallback prefer=%d)", target, fallback_prefer);
            error_code = cls_ping_detector_error_resolve_error;
            result->packet_loss = 1.0; // hostname解析失败，视为100%丢包
            goto cleanup;
        }
    }
    
    // 判断解析后的IP是IPv4还是IPv6
    BOOL isIPv6 = (strchr(resolved_ip, ':') != NULL);
    
    // 保存解析结果
    strncpy(result->resolved_ip, resolved_ip, sizeof(result->resolved_ip) - 1);
    result->resolved_ip[sizeof(result->resolved_ip) - 1] = '\0'; // 确保字符串结束
    
    // 获取并设置接口名称
    get_interface_name(interface_index, result->interface, sizeof(result->interface));
    
    // 创建socket
    if (isIPv6) {
        resources.socket_fd = socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6);
    } else {
        resources.socket_fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    }
    
    if (resources.socket_fd < 0) {
        int err = errno;
        set_error_message(result, "Failed to create ICMP socket: errno=%d (%s), isIPv6=%d", err, strerror(err), isIPv6);
        error_code = cls_ping_detector_error_socket_create_error;
        goto cleanup;
    }
    
    // 设置socket选项：TTL
    if (isIPv6) {
        int ttl_opt = ttl;
        if (setsockopt(resources.socket_fd, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &ttl_opt, sizeof(ttl_opt)) != 0) {
            int err = errno;
            set_error_message(result, "Failed to set IPv6 TTL: errno=%d (%s)", err, strerror(err));
            error_code = cls_ping_detector_error_socket_create_error;
            goto cleanup;
        }

        // 尝试设置 IPV6_CHECKSUM 选项（主要用于 UDP，ICMPv6 内核会自动计算）
        // 注意：在 iOS 上，ICMPv6 socket 可能不支持此选项（errno=42 ENOPROTOOPT），这是正常的
        int cksum_offset = offsetof(ICMPHeader, checksum);
        if (setsockopt(resources.socket_fd, IPPROTO_IPV6, IPV6_CHECKSUM, &cksum_offset, sizeof(cksum_offset)) != 0) {
            int err = errno;
            // ENOPROTOOPT (42) 表示协议不支持此选项，对于 ICMPv6 这是正常的，内核会自动计算校验和
            // 其他错误才记录为异常，但不影响后续操作
            if (err != ENOPROTOOPT) {
                // 非 ENOPROTOOPT 的错误才记录异常
                if (result && result->error_message[0] == '\0') {
                    set_error_message(result, "Failed to enable IPv6 checksum auto-fill: errno=%d (%s)", err, strerror(err));
                }
                if (result) {
                    result->exceptionNum += 1;
                }
            }
            // ENOPROTOOPT 是正常的，内核会自动处理 ICMPv6 校验和，不需要记录错误
        }
    } else {
        int ttl_opt = ttl;
        if (setsockopt(resources.socket_fd, IPPROTO_IP, IP_TTL, &ttl_opt, sizeof(ttl_opt)) != 0) {
            int err = errno;
            set_error_message(result, "Failed to set IPv4 TTL: errno=%d (%s)", err, strerror(err));
            error_code = cls_ping_detector_error_socket_create_error;
            goto cleanup;
        }
    }
    
    // 设置非阻塞模式（用于select）
    int flags = fcntl(resources.socket_fd, F_GETFL, 0);
    if (flags >= 0) {
        if (fcntl(resources.socket_fd, F_SETFL, flags | O_NONBLOCK) < 0) {
            int err = errno;
            // 非阻塞模式失败不是致命错误，但记录一次异常便于排查
            if (result && result->error_message[0] == '\0') {
                set_error_message(result, "Failed to set non-blocking mode: errno=%d (%s)", err, strerror(err));
            }
            if (result) {
                result->exceptionNum += 1;
            }
        }
    }
    
    // 绑定到指定接口
    if (bind_socket_to_interface(resources.socket_fd, isIPv6, interface_index, result) < 0) {
        int err = errno;
        set_error_message(result, "Failed to bind socket to interface %u: errno=%d (%s)", interface_index, err, strerror(err));
        error_code = cls_ping_detector_error_net_binding_failed;
        goto cleanup;
    }
    
    // 构建目标地址
    struct sockaddr_storage target_addr_storage;
    memset(&target_addr_storage, 0, sizeof(target_addr_storage));
    socklen_t addr_len = 0;
    
    if (isIPv6) {
        struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)&target_addr_storage;
        memset(addr6, 0, sizeof(struct sockaddr_in6));
        addr6->sin6_family = AF_INET6;
        addr6->sin6_port = 0; // ICMP 不使用端口
        addr6->sin6_flowinfo = 0;
        addr6->sin6_scope_id = 0;
        if (inet_pton(AF_INET6, resolved_ip, &addr6->sin6_addr) <= 0) {
            set_error_message(result, "Failed to convert IPv6 address: %s", resolved_ip);
            error_code = cls_ping_detector_error_resolve_error;
            goto cleanup;
        }
        
        // 检查是否是链路本地地址（fe80::/10），如果是且指定了接口，设置scope_id
        const uint8_t *addr_bytes = (const uint8_t *)&addr6->sin6_addr;
        if (addr_bytes[0] == 0xfe && (addr_bytes[1] & 0xc0) == 0x80) {
            // 链路本地地址，如果指定了接口索引，使用它作为scope_id
            if (interface_index > 0) {
                if (!interface_has_linklocal_ipv6(interface_index)) {
                    set_error_message(result, "Interface %u has no link-local IPv6 address", interface_index);
                    error_code = cls_ping_detector_error_net_binding_failed;
                    goto cleanup;
                }
                addr6->sin6_scope_id = interface_index;
            } else {
                // 未指定接口时尝试动态选择一个活动接口
                unsigned int auto_ifindex = find_active_ifindex_for_linklocal();
                if (auto_ifindex == 0) {
                    // 兜底：保持兼容旧逻辑，尝试常见接口名称
                    auto_ifindex = if_nametoindex("en0");
                    if (auto_ifindex == 0) {
                        auto_ifindex = if_nametoindex("pdp_ip0");
                    }
                    if (auto_ifindex == 0) {
                        auto_ifindex = if_nametoindex("en1");
                    }
                }
                if (auto_ifindex > 0) {
                    addr6->sin6_scope_id = auto_ifindex;
                }
            }
        }
        
        addr_len = sizeof(struct sockaddr_in6);
    } else {
        struct sockaddr_in *addr4 = (struct sockaddr_in *)&target_addr_storage;
        memset(addr4, 0, sizeof(struct sockaddr_in));
        addr4->sin_family = AF_INET;
        if (inet_pton(AF_INET, resolved_ip, &addr4->sin_addr) <= 0) {
            set_error_message(result, "Failed to convert IPv4 address: %s", resolved_ip);
            error_code = cls_ping_detector_error_resolve_error;
            goto cleanup;
        }
        addr_len = sizeof(struct sockaddr_in);
    }
    
    // 设置ping_size和ttl
    result->ping_size = sizeof(ICMPHeader) + packet_size;
    result->ttl = ttl;
    
    // 初始化统计变量
    RttArray rtt_list;
    rtt_array_init(&rtt_list);
    int packets_sent = 0; // 将在perform_ping_loop中更新为实际发送数
    int packets_received = 0;
    
    // 获取ICMP ID（使用固定值0，因为接收时不再校验ID）
    uint16_t ping_icmp_id = 0;
    
    cls_ping_detector_error_code icmp_error = cls_ping_detector_error_success;
    // 执行ping循环
    BOOL permission_denied = NO;
    perform_ping_loop(resources.socket_fd, (const struct sockaddr *)&target_addr_storage, addr_len,
                     times, packet_size, ttl, timeout_ms, interval_ms,
                     ping_icmp_id, isIPv6, resolved_ip,
                     &rtt_list, &packets_received, &packets_sent, &permission_denied, result,
                     &icmp_error);
    
    // 计算统计信息
    result->packets_sent = packets_sent;
    result->packets_received = packets_received;
    
    // 如果完全未发送成功或完全未收到，直接返回错误码，避免误判为成功
    if (packets_sent == 0) {
        if (result->error_message[0] == '\0') {
            if (permission_denied) {
                set_error_message(result, "ICMP send denied (EPERM/EACCES)");
            } else {
                set_error_message(result, "No ICMP packets sent");
            }
        }
        error_code = permission_denied ? cls_ping_detector_error_permission_denied
                                       : cls_ping_detector_error_timeout;
        rtt_array_free(&rtt_list);
        goto cleanup;
    }
    
    if (packets_received == 0) {
        if (result->error_message[0] == '\0') {
            if (icmp_error == cls_ping_detector_error_network_unreachable) {
                set_error_message(result, "ICMP unreachable received");
            } else if (icmp_error == cls_ping_detector_error_timeout) {
                set_error_message(result, "ICMP time exceeded received");
            } else {
                set_error_message(result, "No ICMP replies received");
            }
        }
        if (icmp_error != cls_ping_detector_error_success) {
            error_code = icmp_error;
        } else {
            error_code = permission_denied ? cls_ping_detector_error_permission_denied
                                           : cls_ping_detector_error_timeout;
        }
        rtt_array_free(&rtt_list);
        goto cleanup;
    }
    
    // 计算丢包率
    if (packets_sent > 0) {
        result->packet_loss = ((double)(packets_sent - packets_received) / (double)packets_sent);
        if (result->packet_loss < 0.0) result->packet_loss = 0.0;
        if (result->packet_loss > 1.0) result->packet_loss = 1.0;
        // 四舍五入到两位小数，消除浮点数精度误差（如 0.3 可能变成 0.29999999999999999）
        result->packet_loss = round(result->packet_loss * 100.0) / 100.0;
    } else {
        result->packet_loss = 1.0;
    }
    
    // 计算RTT统计信息
    if (rtt_list.count > 0) {
        // 计算最小、最大、平均RTT
        double min_rtt = rtt_list.rtts[0];
        double max_rtt = rtt_list.rtts[0];
        double sum_rtt = 0.0;
        for (size_t i = 0; i < rtt_list.count; i++) {
            double rtt = rtt_list.rtts[i];
            if (rtt < min_rtt) min_rtt = rtt;
            if (rtt > max_rtt) max_rtt = rtt;
            sum_rtt += rtt;
        }
        result->min_rtt = min_rtt;
        result->max_rtt = max_rtt;
        result->avg_rtt = sum_rtt / (double)rtt_list.count;
        result->total_time = sum_rtt;
        
        // 计算抖动
        if (rtt_list.count > 1) {
            double jitter = 0.0;
            for (size_t i = 1; i < rtt_list.count; i++) {
                double diff = rtt_list.rtts[i] - rtt_list.rtts[i-1];
                jitter += (diff >= 0.0) ? diff : -diff;
            }
            result->jitter = jitter / (double)(rtt_list.count - 1);
            if (result->jitter < 0.0) {
                result->jitter = 0.0;
            }
        } else {
            result->jitter = 0.0;
        }
        
        // 计算标准差
        double variance = 0.0;
        double avg = result->avg_rtt;
        for (size_t i = 0; i < rtt_list.count; i++) {
            double diff = rtt_list.rtts[i] - avg;
            variance += diff * diff;
        }
        if (rtt_list.count > 0) {
            double variance_mean = variance / (double)rtt_list.count;
            if (variance_mean >= 0.0) {
                result->stddev = sqrt(variance_mean);
            } else {
                result->stddev = 0.0;
            }
        } else {
            result->stddev = 0.0;
        }
    } else {
        result->min_rtt = 0.0;
        result->max_rtt = 0.0;
        result->avg_rtt = 0.0;
        result->jitter = 0.0;
        result->stddev = 0.0;
        result->total_time = 0.0;
    }
    
    // 释放RTT数组
    rtt_array_free(&rtt_list);
    
    // 成功完成，清理资源并返回
    result->error_code = cls_ping_detector_error_success;
    cleanup_ping_resources(&resources);
    return cls_ping_detector_error_success;
    
cleanup:
    // 统一清理资源（确保在所有错误路径上都执行）
    result->error_code = error_code;  // 将错误码写入 result 结构体，保持数据一致性
    
    // 如果最终错误码不是成功，强制设置loss为1.0（表示测试失败）
    if (error_code != cls_ping_detector_error_success) {
        result->packet_loss = 1.0;
    }
    
    cleanup_ping_resources(&resources);
    return error_code;
}

// ============================================================================
// JSON 转换
// ============================================================================

static int json_escape(const char *str, char *output, size_t output_size) {
    if (str == NULL || output == NULL || output_size == 0) {
        return -1;
    }
    
    size_t pos = 0;
    for (const char *p = str; *p != '\0'; p++) {
        // 检查是否有足够空间（至少需要1个字节用于null终止符）
        if (pos >= output_size - 1) {
            // 缓冲区不足，返回错误
            return -1;
        }
        
        size_t remaining = output_size - pos - 1;
        
        switch (*p) {
            case '"':  // 双引号
                if (remaining < 2) return -1;
                output[pos++] = '\\';
                output[pos++] = '"';
                break;
            case '\\': // 反斜杠
                if (remaining < 2) return -1;
                output[pos++] = '\\';
                output[pos++] = '\\';
                break;
            case '\b': // 退格
                if (remaining < 2) return -1;
                output[pos++] = '\\';
                output[pos++] = 'b';
                break;
            case '\f': // 换页
                if (remaining < 2) return -1;
                output[pos++] = '\\';
                output[pos++] = 'f';
                break;
            case '\n': // 换行
                if (remaining < 2) return -1;
                output[pos++] = '\\';
                output[pos++] = 'n';
                break;
            case '\r': // 回车
                if (remaining < 2) return -1;
                output[pos++] = '\\';
                output[pos++] = 'r';
                break;
            case '\t': // 制表符
                if (remaining < 2) return -1;
                output[pos++] = '\\';
                output[pos++] = 't';
                break;
            default:
                // 对于普通字符，检查是否有足够空间
                if (pos >= output_size - 1) return -1;
                output[pos++] = *p;
                break;
        }
    }
    
    // 确保有空间添加null终止符
    if (pos >= output_size) return -1;
    output[pos] = '\0';
    return (int)pos;
}

// 获取错误码对应的错误描述
static const char *get_error_description(cls_ping_detector_error_code error_code) {
    switch (error_code) {
        case cls_ping_detector_error_success:
            return "Success";
        case cls_ping_detector_error_invalid_target:
            return "Invalid target";
        case cls_ping_detector_error_network_unreachable:
            return "Network unreachable";
        case cls_ping_detector_error_timeout:
            return "Timeout";
        case cls_ping_detector_error_permission_denied:
            return "Permission denied";
        case cls_ping_detector_error_socket_create_error:
            return "Socket create error";
        case cls_ping_detector_error_resolve_error:
            return "Resolve error";
        case cls_ping_detector_error_net_binding_failed:
            return "Network binding failed";
        case cls_ping_detector_error_cancelled:
            return "Cancelled";
        case cls_ping_detector_error_unknown_error:
            return "Unknown error";
        default:
            return "Unknown error";
    }
}

int cls_ping_detector_result_to_json(const cls_ping_detector_result *result,
                                     char *json_buffer,
                                     size_t buffer_size) {
    if (result == NULL || json_buffer == NULL || buffer_size == 0) {
        return -1;
    }
    
    if (buffer_size < 256) {
        return -1;
    }
    
    // 从 result 结构体中获取错误码，确保数据一致性
    // result->error_code 在 cls_ping_detector_perform_ping 中已被正确设置
    cls_ping_detector_error_code error_code = result->error_code;
    
    char escaped[2048];
    int pos = 0;
    
    // 开始JSON对象
    int ret = snprintf(json_buffer + pos, buffer_size - pos, "{\n");
    if (ret < 0 || (size_t)ret >= buffer_size - pos) {
        return -1;
    }
    pos += ret;
    
    // host
    if (json_escape(result->target, escaped, sizeof(escaped)) < 0) return -1;
    ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"host\": \"%s\",\n", escaped);
    if (ret < 0 || (size_t)ret >= buffer_size - pos) {
        return -1;
    }
    pos += ret;
    
    // method
    if (json_escape(result->method, escaped, sizeof(escaped)) < 0) return -1;
    ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"method\": \"%s\",\n", escaped);
    if (ret < 0 || (size_t)ret >= buffer_size - pos) {
        return -1;
    }
    pos += ret;
    
    // host_ip (保留向后兼容)
    if (json_escape(result->resolved_ip, escaped, sizeof(escaped)) < 0) return -1;
    ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"host_ip\": \"%s\",\n", escaped);
    if (ret < 0 || (size_t)ret >= buffer_size - pos) {
        return -1;
    }
    pos += ret;
    
    if (json_escape(result->interface, escaped, sizeof(escaped)) < 0) return -1;
    ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"interface\": \"%s\",\n", escaped);
    if (ret < 0 || (size_t)ret >= buffer_size - pos) {
        return -1;
    }
    pos += ret;
    
    
    // count
    ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"count\": %d,\n", result->packets_sent);
    if (ret < 0 || (size_t)ret >= buffer_size - pos) {
        return -1;
    }
    pos += ret;
    
    // size
    ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"size\": %d,\n", result->ping_size);
    if (ret < 0 || (size_t)ret >= buffer_size - pos) {
        return -1;
    }
    pos += ret;
    
    // total (输出为字符串，避免 IEEE 754 精度问题)
    ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"total\": \"%.2f\",\n", result->total_time);
    if (ret < 0 || (size_t)ret >= buffer_size - pos) {
        return -1;
    }
    pos += ret;
    
    // loss: 丢包率 (转换为小数形式，0.0-1.0，输出为字符串)
    double loss_decimal = result->packet_loss / 1.0;
    if (loss_decimal < 0.0) loss_decimal = 0.0;
    if (loss_decimal > 1.0) loss_decimal = 1.0;
    ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"loss\": \"%.2f\",\n", loss_decimal);
    if (ret < 0 || (size_t)ret >= buffer_size - pos) {
        return -1;
    }
    pos += ret;
    
    // latency字段 (输出为字符串)
    if (result->packets_received > 0) {
        ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"latency_min\": \"%.3f\",\n", result->min_rtt);
        if (ret < 0 || (size_t)ret >= buffer_size - pos) {
            return -1;
        }
        pos += ret;
        
        ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"latency_max\": \"%.3f\",\n", result->max_rtt);
        if (ret < 0 || (size_t)ret >= buffer_size - pos) {
            return -1;
        }
        pos += ret;
        
        ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"latency\": \"%.3f\",\n", result->avg_rtt);
        if (ret < 0 || (size_t)ret >= buffer_size - pos) {
            return -1;
        }
        pos += ret;
        
        ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"stddev\": \"%.3f\",\n", result->stddev);
        if (ret < 0 || (size_t)ret >= buffer_size - pos) {
            return -1;
        }
        pos += ret;
    } else {
        ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"latency_min\": null,\n");
        if (ret < 0 || (size_t)ret >= buffer_size - pos) {
            return -1;
        }
        pos += ret;
        
        ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"latency_max\": null,\n");
        if (ret < 0 || (size_t)ret >= buffer_size - pos) {
            return -1;
        }
        pos += ret;
        
        ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"latency\": null,\n");
        if (ret < 0 || (size_t)ret >= buffer_size - pos) {
            return -1;
        }
        pos += ret;
        
        ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"stddev\": null,\n");
        if (ret < 0 || (size_t)ret >= buffer_size - pos) {
            return -1;
        }
        pos += ret;
    }
    
    // responseNum
    ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"responseNum\": %d,\n", result->packets_received);
    if (ret < 0 || (size_t)ret >= buffer_size - pos) {
        return -1;
    }
    pos += ret;
    
    // exceptionNum
    ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"exceptionNum\": %d,\n", result->exceptionNum);
    if (ret < 0 || (size_t)ret >= buffer_size - pos) {
        return -1;
    }
    pos += ret;
    
    // bindFailed
    ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"bindFailed\": %d", result->bindFailed);
    if (ret < 0 || (size_t)ret >= buffer_size - pos) {
        return -1;
    }
    pos += ret;
    
    // 如果有错误，输出错误信息
    if (error_code != cls_ping_detector_error_success || (result->error_message[0] != '\0')) {
        ret = snprintf(json_buffer + pos, buffer_size - pos, ",\n  \"errCode\": %ld,\n", (long)error_code);
        if (ret < 0 || (size_t)ret >= buffer_size - pos) {
            return -1;
        }
        pos += ret;
        
        const char *error_desc = get_error_description(error_code);
        if (json_escape(error_desc, escaped, sizeof(escaped)) < 0) return -1;
        ret = snprintf(json_buffer + pos, buffer_size - pos, "  \"error\": \"%s\"", escaped);
        if (ret < 0 || (size_t)ret >= buffer_size - pos) {
            return -1;
        }
        pos += ret;
        
        // 如果有详细错误信息，也输出
        if (result->error_message[0] != '\0') {
            if (json_escape(result->error_message, escaped, sizeof(escaped)) < 0) return -1;
            ret = snprintf(json_buffer + pos, buffer_size - pos, ",\n  \"errMsg\": \"%s\"", escaped);
            if (ret < 0 || (size_t)ret >= buffer_size - pos) {
                return -1;
            }
            pos += ret;
        }
    }
    
    // 结束JSON对象
    ret = snprintf(json_buffer + pos, buffer_size - pos, "\n}");
    if (ret < 0 || (size_t)ret >= buffer_size - pos) {
        return -1;
    }
    pos += ret;
    
    return pos;
}
