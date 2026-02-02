//
//  cls_dns_detector.m
//  network_ios
//
//  DNS 探测器 - 使用 Network.framework 发送 UDP DNS 查询
//

#import "cls_dns_detector.h"
#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import <arpa/inet.h>
#import <ctype.h>
#import <os/lock.h>
#import <stdatomic.h>
#import <stdlib.h>
#import <string.h>
#import <dlfcn.h>
#import <sys/time.h>
#import <unistd.h>
#import <dispatch/dispatch.h>
#import <ifaddrs.h>
#import <net/if.h>

#define DNS_BUFFER_SIZE 8192
#define DNS_HEADER_SIZE 12
#define DNS_MAX_LABEL_LEN 63
#define DNS_DEFAULT_TIMEOUT_MS 5000
#define DNS_MIN_TIMEOUT_MS 1000
#define DNS_MAX_TIMEOUT_MS 30000
// DNS 记录字段最大长度（与 cls_dns_answer_record 结构体定义保持一致）
#define DNS_MAX_RECORD_NAME_LEN 1024   // 域名最大长度
#define DNS_MAX_RECORD_TYPE_LEN 32     // 记录类型最大长度
#define DNS_MAX_RECORD_VALUE_LEN 4096  // 记录值最大长度

typedef struct {
    uint16_t id;
    uint16_t flags;
    uint16_t qdcount;
    uint16_t ancount;
    uint16_t nscount;
    uint16_t arcount;
} tiny_dns_header;

typedef struct {
    char *name;
    char *type;
    uint32_t ttl;
    char *value;
} DnsAnswerRecord;

typedef struct {
    DnsAnswerRecord *records;
    size_t count;
    size_t capacity;
} DnsAnswerRecordArray;

/**
 * 验证接口索引是否有效
 * @param interface_index 网卡索引，0表示默认
 * @return 0=有效，-1=无效
 */
static int validate_interface_index(unsigned int interface_index) {
    if (interface_index == 0) return 0;
    
    char ifname[IF_NAMESIZE];
    if (if_indextoname(interface_index, ifname) == NULL) {
        return -1;
    }
    return 0;
}

/**
 * 初始化答案记录数组
 * @param array 待初始化的数组
 */
static void dns_answer_record_array_init(DnsAnswerRecordArray *array) {
    if (!array) return;
    array->records = NULL;
    array->count = 0;
    array->capacity = 0;
}

/**
 * 释放答案记录数组占用的内存
 * @param array 待释放的数组
 */
static void dns_answer_record_array_free(DnsAnswerRecordArray *array) {
    if (!array || !array->records) return;
    
    // 释放每个记录中的字符串
    for (size_t i = 0; i < array->count; i++) {
        if (array->records[i].name) {
            free(array->records[i].name);
            array->records[i].name = NULL;
        }
        if (array->records[i].type) {
            free(array->records[i].type);
            array->records[i].type = NULL;
        }
        if (array->records[i].value) {
            free(array->records[i].value);
            array->records[i].value = NULL;
        }
    }
    
    // 释放数组本身
    free(array->records);
    array->records = NULL;
    array->count = 0;
    array->capacity = 0;
}

/**
 * 安全地复制字符串（带长度限制）
 * @param src 源字符串
 * @param max_len 最大长度
 * @return 新分配的字符串，失败返回 NULL（调用者负责释放）
 */
static char *safe_strdup(const char *src, size_t max_len) {
    if (!src) return NULL;
    
    size_t len = strnlen(src, max_len + 1);
    if (len == 0 || len > max_len) return NULL;
    
    char *dst = malloc(len + 1);
    if (!dst) return NULL;
    
    memcpy(dst, src, len);
    dst[len] = '\0';
    return dst;
}

#define DNS_MAX_RECORD_CAPACITY 30  // 与 cls_dns_answer_record answers[30] 保持一致

/**
 * 向答案记录数组添加一条记录
 * @param array 目标数组
 * @param record 待添加的记录
 * @return 0=成功, -1=失败
 */
static int dns_answer_record_array_add(DnsAnswerRecordArray *array, const DnsAnswerRecord *record) {
    if (!array || !record) return -1;
    
    // 检查容量限制
    if (array->count >= DNS_MAX_RECORD_CAPACITY) return -1;
    
    // 动态扩容
    if (array->count >= array->capacity) {
        size_t new_cap = array->capacity == 0 ? 8 : array->capacity * 2;
        if (new_cap > DNS_MAX_RECORD_CAPACITY) new_cap = DNS_MAX_RECORD_CAPACITY;
        
        DnsAnswerRecord *tmp = realloc(array->records, new_cap * sizeof(DnsAnswerRecord));
        if (!tmp) {
            // realloc 失败时，原数组保持不变，直接返回错误
            return -1;
        }
        
        // 初始化新分配的内存
        memset(&tmp[array->count], 0, (new_cap - array->count) * sizeof(DnsAnswerRecord));
        array->records = tmp;
        array->capacity = new_cap;
    }
    
    // 复制记录
    DnsAnswerRecord *dst = &array->records[array->count];
    memset(dst, 0, sizeof(DnsAnswerRecord));
    
    // 按顺序分配内存，如果任何一步失败，清理已分配的资源
    // 注意：record->name, record->type, record->value 可能指向栈上的局部变量
    // 我们必须立即复制它们，因为栈变量在函数返回后就会失效
    if (record->name && record->name[0] != '\0') {
        dst->name = safe_strdup(record->name, DNS_MAX_RECORD_NAME_LEN);
        if (!dst->name) {
            // 内存分配失败，清理并返回
            memset(dst, 0, sizeof(DnsAnswerRecord));
            return -1;
        }
    } else {
        // name 为空或 NULL，设置为 NULL（不分配内存）
        dst->name = NULL;
    }
    
    if (record->type && record->type[0] != '\0') {
        dst->type = safe_strdup(record->type, DNS_MAX_RECORD_TYPE_LEN);
        if (!dst->type) {
            // 内存分配失败，清理已分配的资源
            if (dst->name) {
                free(dst->name);
                dst->name = NULL;
            }
            memset(dst, 0, sizeof(DnsAnswerRecord));
            return -1;
        }
    } else {
        // type 为空或 NULL，设置为 NULL（不分配内存）
        dst->type = NULL;
    }
    
    if (record->value && record->value[0] != '\0') {
        dst->value = safe_strdup(record->value, DNS_MAX_RECORD_VALUE_LEN);
        if (!dst->value) {
            // 内存分配失败，清理已分配的资源
            if (dst->name) {
                free(dst->name);
                dst->name = NULL;
            }
            if (dst->type) {
                free(dst->type);
                dst->type = NULL;
            }
            memset(dst, 0, sizeof(DnsAnswerRecord));
            return -1;
        }
    } else {
        // value 为空或 NULL，设置为 NULL（不分配内存）
        dst->value = NULL;
    }
    
    dst->ttl = record->ttl;
    array->count++;
    return 0;
}

/**
 * 验证域名格式
 * @param domain 待验证的域名
 * @return 0=有效, -1=无效
 */
static int validate_domain(const char *domain) {
    if (!domain) return -1;
    
    size_t len = strlen(domain);
    if (len == 0 || len > 253) return -1; // DNS 域名最大长度为 253
    
    // 检查不能以点开头或结尾
    if (domain[0] == '.' || (len > 0 && domain[len - 1] == '.')) return -1;
    
    size_t label_len = 0;
    BOOL last_was_dot = NO;
    for (size_t i = 0; i < len; i++) {
        char c = domain[i];
        if (c == '.') {
            // 检查连续的点
            if (last_was_dot) return -1;
            last_was_dot = YES;
            // 标签不能为空或超过最大长度
            if (label_len == 0 || label_len > DNS_MAX_LABEL_LEN) return -1;
            label_len = 0;
            continue;
        }
        last_was_dot = NO;
        // 允许字母、数字、连字符、下划线（兼容 SRV/TXT 等记录的前导下划线）
        if (!(isalnum(c) || c == '-' || c == '_')) return -1;
        label_len++;
    }
    // 最后一个标签也要验证
    if (label_len == 0 || label_len > DNS_MAX_LABEL_LEN) return -1;
    return 0;
}

/**
 * 构建 DNS 查询包
 * @param domain 查询的域名
 * @param buffer 输出缓冲区
 * @param buffer_size 缓冲区大小
 * @param query_id 查询 ID
 * @param prefer IP 版本偏好：0=IPv4优先, 1=IPv6优先, 2=IPv4 only, 3=IPv6 only
 * @return 成功返回查询包长度，失败返回 -1
 */
static int build_dns_query(const char *domain, uint8_t *buffer, size_t buffer_size, uint16_t query_id, int prefer) {
    if (!domain || !buffer || buffer_size < 512) return -1;
    if (validate_domain(domain) != 0) return -1;
    if (prefer < 0 || prefer > 3) return -1;
    size_t domain_len = strlen(domain);
    tiny_dns_header *header = (tiny_dns_header *)buffer;
    header->id = htons(query_id);
    header->flags = htons(0x0100);
    header->qdcount = htons(1);
    header->ancount = 0;
    header->nscount = 0;
    header->arcount = 0;
    size_t offset = DNS_HEADER_SIZE;
    size_t label_start = 0;
    for (size_t i = 0; i <= domain_len; i++) {
        if (i == domain_len || domain[i] == '.') {
            if (i > label_start) {
                size_t label_len = i - label_start;
                if (label_len > DNS_MAX_LABEL_LEN) return -1;
                if (offset + label_len + 1 >= buffer_size) return -1;
                buffer[offset++] = (uint8_t)label_len;
                memcpy(&buffer[offset], &domain[label_start], label_len);
                offset += label_len;
            }
            label_start = i + 1;
        }
    }
    if (offset + 1 >= buffer_size) return -1;
    buffer[offset++] = 0;
    if (offset + 4 >= buffer_size) return -1;
    uint16_t qtype = (prefer == 1 || prefer == 3) ? 28 : 1;
    uint16_t qtype_net = htons(qtype);
    memcpy(&buffer[offset], &qtype_net, 2);
    offset += 2;
    uint16_t qclass_net = htons(1);
    memcpy(&buffer[offset], &qclass_net, 2);
    offset += 2;
    
    // 添加 EDNS0 OPT 记录以支持更大的 UDP 响应（4096 字节）
    if (offset + 11 >= buffer_size) return -1;
    buffer[offset++] = 0;  // 根域名（空）
    uint16_t opt_type = htons(41);  // OPT 记录类型
    memcpy(&buffer[offset], &opt_type, 2);
    offset += 2;
    uint16_t udp_payload_size = htons(4096);  // UDP 负载大小
    memcpy(&buffer[offset], &udp_payload_size, 2);
    offset += 2;
    buffer[offset++] = 0;  // 扩展 RCODE 和标志（高4位是扩展RCODE，低4位是标志）
    buffer[offset++] = 0;  // EDNS 版本（必须为0）
    uint16_t z = 0;  // Z 字段（保留，用于DNSSEC等）
    memcpy(&buffer[offset], &z, 2);
    offset += 2;
    uint16_t rdlength = 0;  // 数据长度（无选项时为0）
    memcpy(&buffer[offset], &rdlength, 2);
    offset += 2;
    
    // 更新 arcount（ADDITIONAL 记录数）为 1（EDNS0 OPT 记录）
    header->arcount = htons(1);
    
    return (int)offset;
}

/**
 * 解析 DNS 响应头部
 * @param buffer 响应缓冲区
 * @param buf_len 缓冲区长度
 * @param header 输出参数，解析后的头部
 * @return 0=成功, -1=失败
 */
static int parse_dns_header(const uint8_t *buffer, size_t buf_len, tiny_dns_header *header) {
    if (!buffer || !header || buf_len < DNS_HEADER_SIZE) return -1;
    memcpy(header, buffer, DNS_HEADER_SIZE);
    // 网络字节序转主机字节序
    header->id = ntohs(header->id);
    header->flags = ntohs(header->flags);
    header->qdcount = ntohs(header->qdcount);
    header->ancount = ntohs(header->ancount);
    header->nscount = ntohs(header->nscount);
    header->arcount = ntohs(header->arcount);
    return 0;
}

/**
 * 解析 DNS 名称（支持压缩指针，增强循环检测）
 * @param buffer 响应缓冲区
 * @param buf_len 缓冲区长度
 * @param offset 输入输出参数，当前偏移位置
 * @param name 输出参数，解析后的名称
 * @param name_len 名称缓冲区长度
 * @param depth 递归深度（防止循环引用）
 * @param visited_offsets 已访问的偏移集合（防止循环引用），最多跟踪16个偏移
 * @param visited_count 已访问偏移的数量
 * @return 0=成功, -1=失败
 */
#define DNS_MAX_VISITED_OFFSETS 32  // 增加visited_offsets数组大小，支持更复杂的压缩指针链

static int parse_dns_name_internal(const uint8_t *buffer, size_t buf_len, size_t *offset, char *name, size_t name_len, int depth, size_t visited_offsets[DNS_MAX_VISITED_OFFSETS], int *visited_count) {
    if (!buffer || !offset || !name || name_len == 0 || depth > 10 || !visited_offsets || !visited_count) return -1; // 最大递归深度 10
    if (*visited_count >= DNS_MAX_VISITED_OFFSETS) return -1; // 防止visited_offsets溢出
    
    size_t pos = *offset;
    
    // 检查当前偏移是否已被访问（防止循环引用）
    for (int i = 0; i < *visited_count; i++) {
        if (visited_offsets[i] == pos) {
            return -1; // 检测到循环引用
        }
    }
    
    // 记录当前偏移
    if (*visited_count < DNS_MAX_VISITED_OFFSETS) {
        visited_offsets[*visited_count] = pos;
        (*visited_count)++;
    } else {
        return -1; // visited_offsets已满，可能是恶意数据包
    }
    
    size_t out_pos = 0;
    while (pos < buf_len) {
        uint8_t len = buffer[pos++];
        if (len == 0) {
            break;
        }
        if ((len & 0xC0) == 0xC0) {
            if (pos >= buf_len) return -1;
            uint8_t next = buffer[pos++];
            uint16_t ptr = ((len & 0x3F) << 8) | next;
            size_t new_offset = ptr;
            if (new_offset >= buf_len) return -1;
            if (new_offset < DNS_HEADER_SIZE) return -1; // 压缩指针不能指向头部区域
            
            // 检查新偏移是否已在访问列表中（防止循环）
            for (int i = 0; i < *visited_count; i++) {
                if (visited_offsets[i] == new_offset) {
                    return -1; // 检测到循环引用
                }
            }
            
            // 递归解析，传递已访问偏移集合
            size_t new_visited[DNS_MAX_VISITED_OFFSETS];
            int new_visited_count = 0;
            // 复制已访问的偏移（包括当前偏移）
            for (int i = 0; i < *visited_count && i < DNS_MAX_VISITED_OFFSETS; i++) {
                new_visited[i] = visited_offsets[i];
                new_visited_count++;
            }
            if (parse_dns_name_internal(buffer, buf_len, &new_offset, name + out_pos, name_len - out_pos, depth + 1, new_visited, &new_visited_count) != 0) return -1;
            *offset = pos;
            return 0;
        }
        if (pos + len > buf_len) return -1;
        // 增强边界检查：确保有足够空间（包括点、标签内容和null终止符）
        if (out_pos + len + 2 >= name_len) return -1;  // +2 for '.' and '\0'
        if (out_pos > 0) {
            name[out_pos++] = '.';
        }
        // 再次检查边界，防止在添加点后溢出
        if (out_pos + len + 1 >= name_len) return -1;
        memcpy(&name[out_pos], &buffer[pos], len);
        out_pos += len;
        pos += len;
    }
    // 最终检查：确保有空间添加null终止符
    if (out_pos >= name_len) return -1;
    name[out_pos] = '\0';
    *offset = pos;
    return 0;
}

/**
 * 解析 DNS 名称（支持压缩指针）
 * @param buffer 响应缓冲区
 * @param buf_len 缓冲区长度
 * @param offset 输入输出参数，当前偏移位置
 * @param name 输出参数，解析后的名称
 * @param name_len 名称缓冲区长度
 * @param depth 递归深度（防止循环引用）
 * @return 0=成功, -1=失败
 */
static int parse_dns_name(const uint8_t *buffer, size_t buf_len, size_t *offset, char *name, size_t name_len, int depth) {
    size_t visited_offsets[DNS_MAX_VISITED_OFFSETS] = {0};
    int visited_count = 0;
    return parse_dns_name_internal(buffer, buf_len, offset, name, name_len, depth, visited_offsets, &visited_count);
}

/**
 * 校验 DNS 响应的问题节是否与请求匹配
 * @param buffer 响应缓冲区
 * @param buf_len 缓冲区长度
 * @param header DNS 头部
 * @param expected_domain 期望的域名
 * @param expected_qtype 期望的查询类型（1=A, 28=AAAA）
 * @return 0=匹配, -1=不匹配
 */
static int validate_dns_question_section(const uint8_t *buffer, size_t buf_len, const tiny_dns_header *header,
                                         const char *expected_domain, uint16_t expected_qtype) {
    if (!buffer || !header || !expected_domain) return -1;
    if (header->qdcount != 1) return -1; // 只支持单个问题
    
    size_t offset = DNS_HEADER_SIZE;
    char qname[1024] = {0};
    if (parse_dns_name(buffer, buf_len, &offset, qname, sizeof(qname), 0) != 0) return -1;
    if (offset + 4 > buf_len) return -1;
    
    // 规范化域名比较（去除末尾的点）
    size_t qname_len = strlen(qname);
    if (qname_len > 0 && qname[qname_len - 1] == '.') {
        qname[qname_len - 1] = '\0';
    }
    
    // 比较域名（不区分大小写）
    if (strcasecmp(qname, expected_domain) != 0) return -1;
    
    // 读取查询类型和类
    uint16_t qtype = ntohs(*(const uint16_t *)(&buffer[offset]));
    uint16_t qclass = ntohs(*(const uint16_t *)(&buffer[offset + 2]));
    
    // 校验查询类型和类
    if (qtype != expected_qtype || qclass != 1) return -1; // 类必须是 IN (1)
    
    // 额外验证：检查响应码（RCODE）是否合理
    uint8_t rcode = (header->flags & 0x0F);
    if (rcode > 5) {
        // RCODE 应该在 0-5 之间（0=NOERROR, 1=FORMERR, 2=SERVFAIL, 3=NXDOMAIN, 4=NOTIMP, 5=REFUSED）
        // 如果超过5，可能是格式错误
        return -1;
    }
    
    // 验证响应标志：QR位必须为1（这是响应）
    if ((header->flags & 0x8000) == 0) {
        return -1; // 不是响应包
    }
    
    return 0;
}

/**
 * 解析 DNS 响应中的答案记录
 * @param buffer 响应缓冲区
 * @param buf_len 缓冲区长度
 * @param header DNS 头部
 * @param array 输出参数，答案记录数组（只包含ANSWER和ADDITIONAL记录，不包含AUTHORITY记录）
 * @return 0=成功, -1=失败
 */
static int dns_detector_parse_answers(const uint8_t *buffer, size_t buf_len, const tiny_dns_header *header, DnsAnswerRecordArray *array) {
    if (!buffer || !header || !array) return -1;
    size_t offset = DNS_HEADER_SIZE;
    for (int i = 0; i < header->qdcount; i++) {
        char qname[1024] = {0};
        if (parse_dns_name(buffer, buf_len, &offset, qname, sizeof(qname), 0) != 0) return -1;
        if (offset + 4 > buf_len) return -1;
        offset += 4;
    }
    for (int i = 0; i < header->ancount; i++) {
        char name[1024] = {0};
        if (parse_dns_name(buffer, buf_len, &offset, name, sizeof(name), 0) != 0) return -1;
        if (offset + 10 > buf_len) return -1;
        uint16_t type = ntohs(*(const uint16_t *)(&buffer[offset])); offset += 2;
        offset += 2; // class
        uint32_t ttl = ntohl(*(const uint32_t *)(&buffer[offset])); offset += 4;
        uint16_t rdlength = ntohs(*(const uint16_t *)(&buffer[offset])); offset += 2;
        if (offset + rdlength > buf_len) return -1;
        
        // 初始化记录结构（确保所有字段为 NULL 或有效值）
        DnsAnswerRecord record = {0};
        record.ttl = ttl;
        
        // 设置 name（使用栈上的局部变量，dns_answer_record_array_add 会复制到堆上）
        // 注意：如果 name 为空，设置为 NULL 而不是空字符串，避免混淆
        record.name = (name[0] != '\0') ? name : NULL;
        
        // 根据记录类型解析值
        if (type == 1 && rdlength == 4) { // A
            char ip[INET_ADDRSTRLEN] = {0};
            if (inet_ntop(AF_INET, &buffer[offset], ip, sizeof(ip))) {
                record.type = "A";
                record.value = ip;  // 栈变量，会被复制
            }
        } else if (type == 28 && rdlength == 16) { // AAAA
            char ip6[INET6_ADDRSTRLEN] = {0};
            if (inet_ntop(AF_INET6, &buffer[offset], ip6, sizeof(ip6))) {
                record.type = "AAAA";
                record.value = ip6;  // 栈变量，会被复制
            }
        } else if (type == 5) { // CNAME
            char cname[1024] = {0};
            size_t cname_offset = offset;
            if (parse_dns_name(buffer, buf_len, &cname_offset, cname, sizeof(cname), 0) == 0) {
                record.type = "CNAME";
                record.value = cname;  // 栈变量，会被复制
            }
        } else if (type == 16) { // TXT
            if (rdlength > 0) {
                // TXT记录可以包含多个字符串，每个字符串前面有一个长度字节
                char txt[512] = {0};  // 缓冲区大小与存储结构体一致
                size_t txt_pos = 0;
                size_t txt_offset = offset;
                size_t remaining = rdlength;
                
                // 解析所有字符串片段
                while (remaining > 0 && txt_pos < sizeof(txt) - 1) {
                    if (txt_offset >= buf_len) break;
                    uint8_t txt_len = buffer[txt_offset];
                    if (txt_len == 0) break;  // 长度为0表示结束
                    if ((size_t)txt_len + 1 > remaining) break;  // 长度超出剩余数据
                    if (txt_len >= 255) break;  // 无效长度
                    
                    txt_offset++;  // 跳过长度字节
                    remaining--;
                    
                    if (txt_offset + txt_len > buf_len) break;
                    if (txt_pos + txt_len + 1 >= sizeof(txt)) break;  // 防止溢出
                    
                    // 如果不是第一个字符串，添加空格分隔
                    if (txt_pos > 0 && txt[txt_pos - 1] != ' ') {
                        txt[txt_pos++] = ' ';
                    }
                    
                    // 复制字符串内容
                    size_t copy_len = ((size_t)txt_len < sizeof(txt) - txt_pos - 1) ? (size_t)txt_len : (sizeof(txt) - txt_pos - 1);
                    memcpy(&txt[txt_pos], &buffer[txt_offset], copy_len);
                    txt_pos += copy_len;
                    txt_offset += txt_len;
                    remaining -= txt_len;
                }
                
                if (txt_pos > 0) {
                    txt[txt_pos] = '\0';  // 确保以 null 结尾
                    record.type = "TXT";
                    record.value = txt;  // 栈变量，会被复制
                }
            }
        } else if (type == 15) { // MX (Mail Exchange)
            if (rdlength >= 3) {
                uint16_t preference = ntohs(*(const uint16_t *)(&buffer[offset]));
                char mx_name[1024] = {0};
                size_t mx_offset = offset + 2;
                if (parse_dns_name(buffer, buf_len, &mx_offset, mx_name, sizeof(mx_name), 0) == 0) {
                    char mx_value[1024] = {0};
                    snprintf(mx_value, sizeof(mx_value), "%u %s", preference, mx_name);
                    record.type = "MX";
                    record.value = mx_value;
                }
            }
        } else if (type == 2) { // NS (Name Server)
            char ns_name[1024] = {0};
            size_t ns_offset = offset;
            if (parse_dns_name(buffer, buf_len, &ns_offset, ns_name, sizeof(ns_name), 0) == 0) {
                record.type = "NS";
                record.value = ns_name;
            }
        } else if (type == 6) { // SOA (Start of Authority)
            char soa_mname[1024] = {0};
            size_t soa_offset = offset;
            if (parse_dns_name(buffer, buf_len, &soa_offset, soa_mname, sizeof(soa_mname), 0) == 0) {
                char soa_rname[1024] = {0};
                if (parse_dns_name(buffer, buf_len, &soa_offset, soa_rname, sizeof(soa_rname), 0) == 0) {
                    if (soa_offset + 20 <= buf_len) {
                        uint32_t serial = ntohl(*(const uint32_t *)(&buffer[soa_offset])); soa_offset += 4;
                        uint32_t refresh = ntohl(*(const uint32_t *)(&buffer[soa_offset])); soa_offset += 4;
                        uint32_t retry = ntohl(*(const uint32_t *)(&buffer[soa_offset])); soa_offset += 4;
                        uint32_t expire = ntohl(*(const uint32_t *)(&buffer[soa_offset])); soa_offset += 4;
                        uint32_t minimum = ntohl(*(const uint32_t *)(&buffer[soa_offset]));
                        char soa_value[2048] = {0};
                        snprintf(soa_value, sizeof(soa_value), "%s %s %u %u %u %u %u",
                                soa_mname, soa_rname, serial, refresh, retry, expire, minimum);
                        record.type = "SOA";
                        record.value = soa_value;
                    }
                }
            }
        } else if (type == 33) { // SRV (Service)
            if (rdlength >= 7) {
                size_t srv_data_offset = offset;
                uint16_t priority = ntohs(*(const uint16_t *)(&buffer[srv_data_offset])); srv_data_offset += 2;
                uint16_t weight = ntohs(*(const uint16_t *)(&buffer[srv_data_offset])); srv_data_offset += 2;
                uint16_t port = ntohs(*(const uint16_t *)(&buffer[srv_data_offset])); srv_data_offset += 2;
                char srv_target[1024] = {0};
                size_t srv_offset = srv_data_offset;
                if (parse_dns_name(buffer, buf_len, &srv_offset, srv_target, sizeof(srv_target), 0) == 0) {
                    char srv_value[2048] = {0};
                    snprintf(srv_value, sizeof(srv_value), "%u %u %u %s", priority, weight, port, srv_target);
                    record.type = "SRV";
                    record.value = srv_value;
                }
            }
        } else if (type == 257) { // CAA (Certification Authority Authorization)
            if (rdlength >= 2) {
                uint8_t flags = buffer[offset];
                uint8_t tag_len = buffer[offset + 1];
                if (tag_len > 0 && (size_t)tag_len + 2 <= rdlength) {
                    char tag[256] = {0};
                    size_t tag_copy_len = ((size_t)tag_len < sizeof(tag) - 1) ? (size_t)tag_len : (sizeof(tag) - 1);
                    memcpy(tag, &buffer[offset + 2], tag_copy_len);
                    tag[tag_copy_len] = '\0';
                    size_t value_len = rdlength - 2 - tag_len;
                    if (value_len > 0 && value_len < 1024) {
                        char value[1024] = {0};
                        memcpy(value, &buffer[offset + 2 + tag_len], value_len);
                        value[value_len] = '\0';
                        char caa_value[1536] = {0};
                        snprintf(caa_value, sizeof(caa_value), "%u %s \"%s\"", flags, tag, value);
                        record.type = "CAA";
                        record.value = caa_value;
                    }
                }
            }
        }
        
        // 只有当 type 和 value 都有效时才添加记录
        // 注意：dns_answer_record_array_add 会复制所有字符串到堆上
        if (record.type && record.value && record.value[0] != '\0') {
            if (dns_answer_record_array_add(array, &record) != 0) {
                // 添加失败，但继续处理其他记录（不返回错误）
                // 这样可以尽可能多地解析记录
            }
        }
        
        offset += rdlength;
    }
    
    // 跳过 AUTHORITY 记录（不解析，不输出）
    for (int i = 0; i < header->nscount; i++) {
        // 跳过名称
        char name[1024] = {0};
        if (parse_dns_name(buffer, buf_len, &offset, name, sizeof(name), 0) != 0) return -1;
        if (offset + 10 > buf_len) return -1;
        // 跳过类型、类、TTL
        offset += 2; // type
        offset += 2; // class
        offset += 4; // ttl
        // 读取数据长度，然后跳过数据
        uint16_t rdlength = ntohs(*(const uint16_t *)(&buffer[offset])); offset += 2;
        if (offset + rdlength > buf_len) return -1;
        // 跳过记录数据
        offset += rdlength;
    }
    
    // 解析 ADDITIONAL 记录
    for (int i = 0; i < header->arcount; i++) {
        char name[1024] = {0};
        if (parse_dns_name(buffer, buf_len, &offset, name, sizeof(name), 0) != 0) return -1;
        if (offset + 10 > buf_len) return -1;
        uint16_t type = ntohs(*(const uint16_t *)(&buffer[offset])); offset += 2;
        uint16_t class = ntohs(*(const uint16_t *)(&buffer[offset])); offset += 2;
        (void)class;  // 读取但未使用，用于跳过 DNS 记录中的 class 字段
        uint32_t ttl = ntohl(*(const uint32_t *)(&buffer[offset])); offset += 4;
        uint16_t rdlength = ntohs(*(const uint16_t *)(&buffer[offset])); offset += 2;
        if (offset + rdlength > buf_len) return -1;
        
        // 跳过 EDNS0 OPT 记录（类型 41），它不是实际的 DNS 记录数据
        if (type == 41) {
            offset += rdlength;
            continue;
        }
        
        DnsAnswerRecord record = {0};
        record.ttl = ttl;
        record.name = (name[0] != '\0') ? name : NULL;
        
        // 解析 ADDITIONAL 中常见的 A/AAAA 记录（用于 NS 记录的 glue）
        if (type == 1 && rdlength == 4) { // A
            char ip[INET_ADDRSTRLEN] = {0};
            if (inet_ntop(AF_INET, &buffer[offset], ip, sizeof(ip))) {
                record.type = "A";
                record.value = ip;
            }
        } else if (type == 28 && rdlength == 16) { // AAAA
            char ip6[INET6_ADDRSTRLEN] = {0};
            if (inet_ntop(AF_INET6, &buffer[offset], ip6, sizeof(ip6))) {
                record.type = "AAAA";
                record.value = ip6;
            }
        }
        
        if (record.type && record.value && record.value[0] != '\0') {
            if (dns_answer_record_array_add(array, &record) != 0) {
                // 添加失败，继续处理
            }
        }
        
        offset += rdlength;
    }
    
    // 如果应该解析记录但没有任何记录被成功添加，返回错误
    // 注意：对于某些DNS响应（如NXDOMAIN），可能没有答案记录，这是正常的
    // 但如果header显示有答案记录，但解析后array为空，可能是解析失败
    // 注意：AUTHORITY记录已被跳过，不参与此检查
    if ((header->ancount > 0 || header->arcount > 1) && array->count == 0) {
        // 有记录应该被解析，但没有任何记录被添加，可能是解析失败
    }
    
    return 0;
}

/**
 * JSON 字符串转义
 * @param str 源字符串
 * @param output 输出缓冲区
 * @param output_size 缓冲区大小
 * @return 成功返回转义后的长度，失败返回 -1
 */
static int json_escape(const char *str, char *output, size_t output_size) {
    if (!str || !output || output_size == 0) return -1;
    
    size_t pos = 0;
    for (const char *p = str; *p != '\0'; p++) {
        // 检查是否有足够空间（至少需要1个字节用于null终止符）
        if (pos >= output_size - 1) {
            // 缓冲区不足，返回错误
            return -1;
        }
        
        switch (*p) {
            case '"':  // 双引号
                if (pos + 2 >= output_size) return -1; // 检查是否有足够空间
                output[pos++] = '\\';
                output[pos++] = '"';
                break;
            case '\\': // 反斜杠
                if (pos + 2 >= output_size) return -1;
                output[pos++] = '\\';
                output[pos++] = '\\';
                break;
            case '\b': // 退格
                if (pos + 2 >= output_size) return -1;
                output[pos++] = '\\';
                output[pos++] = 'b';
                break;
            case '\f': // 换页
                if (pos + 2 >= output_size) return -1;
                output[pos++] = '\\';
                output[pos++] = 'f';
                break;
            case '\n': // 换行
                if (pos + 2 >= output_size) return -1;
                output[pos++] = '\\';
                output[pos++] = 'n';
                break;
            case '\r': // 回车
                if (pos + 2 >= output_size) return -1;
                output[pos++] = '\\';
                output[pos++] = 'r';
                break;
            case '\t': // 制表符
                if (pos + 2 >= output_size) return -1;
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

static int dns_result_to_json(const char *domain,
                              const char *server_addr,
                              const tiny_dns_header *header,
                              const DnsAnswerRecordArray *answers,
                              size_t recv_len,
                              int prefer,
                              int query_time_ms,
                              char *json_buffer,
                              size_t buffer_size) {
    (void)recv_len;
    char escaped[2048];
    int pos = 0;
    uint16_t flags = header->flags;
    uint8_t rcode = flags & 0x0F;
    const char *status;
    switch (rcode) {
        case 0: status = "NOERROR"; break;
        case 1: status = "FORMERR"; break;
        case 2: status = "SERVFAIL"; break;
        case 3: status = "NXDOMAIN"; break;
        case 4: status = "NOTIMP"; break;
        case 5: status = "REFUSED"; break;
        default: status = "UNKNOWN"; break;
    }
    char flags_str[64] = {0};
    size_t flag_pos = 0; int flag_count = 0;
    if (flags & 0x8000) { memcpy(&flags_str[flag_pos], "qr", 2); flag_pos += 2; flag_count++; }
    if (flags & 0x0400) { if (flag_count++) flags_str[flag_pos++] = ' '; memcpy(&flags_str[flag_pos], "aa", 2); flag_pos += 2; }
    if (flags & 0x0200) { if (flag_count++) flags_str[flag_pos++] = ' '; memcpy(&flags_str[flag_pos], "tc", 2); flag_pos += 2; }
    if (flags & 0x0100) { if (flag_count++) flags_str[flag_pos++] = ' '; memcpy(&flags_str[flag_pos], "rd", 2); flag_pos += 2; }
    if (flags & 0x0080) { if (flag_count++) flags_str[flag_pos++] = ' '; memcpy(&flags_str[flag_pos], "ra", 2); flag_pos += 2; }
    if (flag_count == 0) strcpy(flags_str, "none"); else flags_str[flag_pos] = '\0';

    int n = snprintf(json_buffer + pos, buffer_size - pos, "{\n");
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1; pos += n;
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"method\": \"dns\",\n"); if (n < 0 || (size_t)n >= buffer_size - pos) return -1; pos += n;
    if (json_escape(domain, escaped, sizeof(escaped)) < 0) return -1; // 检查转义是否成功
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"domain\": \"%s\",\n", escaped); if (n < 0 || (size_t)n >= buffer_size - pos) return -1; pos += n;
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"status\": \"%s\",\n", status); if (n < 0 || (size_t)n >= buffer_size - pos) return -1; pos += n;
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"id\": %u,\n", header->id); if (n < 0 || (size_t)n >= buffer_size - pos) return -1; pos += n;
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"flags\": \"%s\",\n", flags_str); if (n < 0 || (size_t)n >= buffer_size - pos) return -1; pos += n;
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"latency\": %.3f,\n", (double)query_time_ms); if (n < 0 || (size_t)n >= buffer_size - pos) return -1; pos += n;
    if (server_addr && server_addr[0]) { 
        if (json_escape(server_addr, escaped, sizeof(escaped)) < 0) return -1; // 检查转义是否成功
        n = snprintf(json_buffer + pos, buffer_size - pos, "  \"host_ip\": \"%s\",\n", escaped); 
    }
    else { n = snprintf(json_buffer + pos, buffer_size - pos, "  \"host_ip\": null,\n"); }
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1; pos += n;
    const char *qtype_str = (prefer == 1 || prefer == 3) ? "AAAA" : "A";
    // 转义domain用于JSON输出
    char escaped_domain[2048];
    if (json_escape(domain, escaped_domain, sizeof(escaped_domain)) < 0) return -1;
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"QUESTION-SECTION\": [\n    {\"name\": \"%s.\", \"type\": \"%s\"}\n  ],\n", escaped_domain, qtype_str);
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1; pos += n;
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"ANSWER-SECTION\": [\n"); if (n < 0 || (size_t)n >= buffer_size - pos) return -1; pos += n;
    for (size_t i = 0; i < answers->count; i++) {
        if (i > 0) { n = snprintf(json_buffer + pos, buffer_size - pos, ",\n"); if (n < 0 || (size_t)n >= buffer_size - pos) return -1; pos += n; }
        const DnsAnswerRecord *ans = &answers->records[i];
        const char *name = ans->name ? ans->name : "";
        const char *atype = ans->type ? ans->type : "";
        const char *value = ans->value ? ans->value : "";
        if (json_escape(name, escaped, sizeof(escaped)) < 0) return -1; // 检查转义是否成功
        n = snprintf(json_buffer + pos, buffer_size - pos, "    {\"name\": \"%s\", \"ttl\": %u, \"atype\": \"", escaped, ans->ttl);
        if (n < 0 || (size_t)n >= buffer_size - pos) return -1; pos += n;
        if (json_escape(atype, escaped, sizeof(escaped)) < 0) return -1; // 检查转义是否成功
        n = snprintf(json_buffer + pos, buffer_size - pos, "%s\", \"value\": \"", escaped);
        if (n < 0 || (size_t)n >= buffer_size - pos) return -1; pos += n;
        if (json_escape(value, escaped, sizeof(escaped)) < 0) return -1; // 检查转义是否成功
        n = snprintf(json_buffer + pos, buffer_size - pos, "%s\"}", escaped);
        if (n < 0 || (size_t)n >= buffer_size - pos) return -1; pos += n;
    }
    n = snprintf(json_buffer + pos, buffer_size - pos, "\n  ]\n}");
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    return pos + n;
}

static uint64_t now_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000 + (uint64_t)tv.tv_usec / 1000;
}

/**
 * 使用 Network.framework 通过 TCP 发送 DNS 查询（用于处理 TC 截断响应）
 * @param payload 查询数据
 * @param payload_len 数据长度
 * @param server DNS 服务器地址
 * @param timeout_ms 超时时间（毫秒）
 * @param interface_index 网卡索引
 * @param recv_buffer 接收缓冲区
 * @param recv_len 输出参数，接收长度
 * @param query_time_ms 输出参数，查询耗时
 * @return 错误码
 */
static int send_dns_with_network_tcp(const uint8_t *payload,
                                    size_t payload_len,
                                    const char *server,
                                    int timeout_ms,
                                    unsigned int interface_index,
                                    uint8_t *recv_buffer,
                                    size_t *recv_len,
                                    int *query_time_ms) {
    if (!payload || !server || !recv_buffer || !recv_len || !query_time_ms) {
        return cls_dns_detector_error_invalid_param;
    }
    
    *recv_len = 0;
    *query_time_ms = 0;
    
    __block int ret = cls_dns_detector_error_send_failed;
    __block dispatch_data_t response = NULL;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    if (!sema) {
        return cls_dns_detector_error_send_failed;
    }
    
    // 状态变量多线程访问，使用 unfair lock 保护
    __block os_unfair_lock state_lock = OS_UNFAIR_LOCK_INIT;
    __block BOOL is_completed = NO;
    __block BOOL has_sent = NO;
    __block BOOL has_received = NO;
    __block BOOL conn_cancelled = NO; // 确保仅取消一次，避免重复日志
    
    // Network.framework 资源
    __block nw_endpoint_t endpoint = NULL;
    __block nw_parameters_t params = NULL;
    __block nw_protocol_stack_t protocol_stack = NULL;
    __block nw_protocol_options_t tcp_options = NULL;
    __block nw_connection_t conn = NULL;
    
    // 统一清理函数
    void (^cleanup_resources)(void) = ^{
        os_unfair_lock_lock(&state_lock);
        if (conn && !conn_cancelled) { 
            nw_connection_cancel(conn); 
            conn_cancelled = YES;
        }
        if (conn) {
            conn = NULL; 
        }
        os_unfair_lock_unlock(&state_lock);
        tcp_options = NULL;
        protocol_stack = NULL;
        params = NULL;
        endpoint = NULL;
        response = NULL;
    };
    
    endpoint = nw_endpoint_create_host(server, "53");
    if (!endpoint) { cleanup_resources(); return cls_dns_detector_error_send_failed; }
    
    params = nw_parameters_create();
    if (!params) { cleanup_resources(); return cls_dns_detector_error_send_failed; }
    
    protocol_stack = nw_parameters_copy_default_protocol_stack(params);
    if (protocol_stack) {
        tcp_options = nw_tcp_create_options();
        if (tcp_options) {
            nw_protocol_stack_set_transport_protocol(protocol_stack, tcp_options);
        }
    }
    
    // 设置网卡绑定
    nw_interface_t required_interface = NULL;
    if (interface_index > 0) {
        if (@available(iOS 13.0, *)) {
            static nw_interface_t (*p_nw_interface_create_with_index)(uint32_t) = NULL;
            static void (*p_nw_parameters_set_required_interface)(nw_parameters_t, nw_interface_t) = NULL;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                p_nw_interface_create_with_index = (nw_interface_t (*)(uint32_t))dlsym(RTLD_DEFAULT, "nw_interface_create_with_index");
                p_nw_parameters_set_required_interface = (void (*)(nw_parameters_t, nw_interface_t))dlsym(RTLD_DEFAULT, "nw_parameters_set_required_interface");
            });
            if (p_nw_interface_create_with_index && p_nw_parameters_set_required_interface) {
                required_interface = p_nw_interface_create_with_index(interface_index);
                if (required_interface) {
                    p_nw_parameters_set_required_interface(params, required_interface);
                }
            }
        }
    }
    
    if (interface_index > 0 && required_interface == NULL) {
        BOOL interface_found = NO;
        struct ifaddrs *ifaddrs_list = NULL;
        if (getifaddrs(&ifaddrs_list) == 0) {
            for (struct ifaddrs *ifa = ifaddrs_list; ifa != NULL; ifa = ifa->ifa_next) {
                if (ifa->ifa_name && if_nametoindex(ifa->ifa_name) == interface_index) {
                    interface_found = YES;
                    BOOL is_wifi = NO;
                    BOOL is_cellular = NO;
                    if (ifa->ifa_flags & IFF_UP) {
                        const char *if_name = ifa->ifa_name;
                        if (ifa->ifa_addr) {
                            if (ifa->ifa_addr->sa_family == AF_INET || ifa->ifa_addr->sa_family == AF_INET6) {
                                // 根据接口名称模式判断（iOS接口命名规则）
                                if (strncmp(if_name, "en", 2) == 0) {
                                    // en0通常是WiFi，检查接口是否不是loopback且是UP状态
                                    if (!(ifa->ifa_flags & IFF_LOOPBACK) && (ifa->ifa_flags & IFF_UP)) {
                                        is_wifi = YES;
                                    }
                                } else if (strncmp(if_name, "pdp_ip", 6) == 0) {
                                    // pdp_ip* 是蜂窝网络接口
                                    is_cellular = YES;
                                } else if (strncmp(if_name, "ipsec", 5) == 0 || 
                                          strncmp(if_name, "utun", 4) == 0) {
                                    // ipsec* 和 utun* 通常是VPN接口，归类为蜂窝网络类型
                                    is_cellular = YES;
                                }
                            }
                        }
                    }
                    if (is_wifi) {
                        nw_parameters_set_required_interface_type(params, nw_interface_type_wifi);
                    } else if (is_cellular) {
                        nw_parameters_set_required_interface_type(params, nw_interface_type_cellular);
                    }
                    break;
                }
            }
            freeifaddrs(ifaddrs_list);
            if (!interface_found) {
                cleanup_resources();
                return cls_dns_detector_error_invalid_param;
            }
        } else {
            cleanup_resources();
            return cls_dns_detector_error_invalid_param;
        }
    }

    // 已设置 required_interface 后释放本地引用（parameters 会持有）
    if (required_interface) {
        required_interface = NULL;
    }
    
    conn = nw_connection_create(endpoint, params);
    if (!conn) { cleanup_resources(); return cls_dns_detector_error_send_failed; }
    
    nw_connection_set_queue(conn, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    uint64_t start = now_ms();
    
    // 安全完成操作
    void (^complete_operation)(int) = ^(int error_code) {
        os_unfair_lock_lock(&state_lock);
        if (is_completed) { os_unfair_lock_unlock(&state_lock); return; }
        is_completed = YES;
        ret = error_code;
        os_unfair_lock_unlock(&state_lock);
        dispatch_semaphore_signal(sema);
    };
    
    // TCP 连接状态处理
    nw_connection_set_state_changed_handler(conn, ^(nw_connection_state_t state, nw_error_t  _Nullable error) {
        os_unfair_lock_lock(&state_lock);
        BOOL completed = is_completed;
        os_unfair_lock_unlock(&state_lock);
        if (completed) return;
        
        if (state == nw_connection_state_ready) {
            // TCP 连接就绪，发送 DNS 查询（TCP 格式：2字节长度 + 查询数据）
            if (!has_sent) {
                os_unfair_lock_lock(&state_lock);
                has_sent = YES;
                os_unfair_lock_unlock(&state_lock);
                
                // TCP DNS 格式：前2字节是长度（网络字节序）
                uint16_t tcp_length = htons((uint16_t)payload_len);
                uint8_t *tcp_payload = malloc(payload_len + 2);
                if (!tcp_payload) {
                    complete_operation(cls_dns_detector_error_send_failed);
                    return;
                }
                memcpy(tcp_payload, &tcp_length, 2);
                memcpy(tcp_payload + 2, payload, payload_len);
                
                // 注意：dispatch_data_create 设置了 DISPATCH_DATA_DESTRUCTOR_FREE，
                // 会自动释放 tcp_payload，不需要手动 free
                dispatch_data_t content = dispatch_data_create(tcp_payload, payload_len + 2, NULL, DISPATCH_DATA_DESTRUCTOR_FREE);
                if (!content) {
                    // 如果创建失败，需要手动释放内存
                    free(tcp_payload);
                    complete_operation(cls_dns_detector_error_send_failed);
                    return;
                }
                nw_connection_send(conn, content, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t  _Nullable send_error) {
                    // tcp_payload 由 dispatch_data 自动释放，不需要手动 free
                    os_unfair_lock_lock(&state_lock);
                    BOOL completed_inner = is_completed;
                    os_unfair_lock_unlock(&state_lock);
                    if (completed_inner) return;
                    
                    if (send_error) {
                        complete_operation(cls_dns_detector_error_send_failed);
                    } else {
                        // 接收响应
                        nw_connection_receive_message(conn, ^(dispatch_data_t  _Nullable content, nw_content_context_t  _Nullable context, bool is_complete, nw_error_t  _Nullable recv_error) {
                            os_unfair_lock_lock(&state_lock);
                            BOOL completed_recv = is_completed;
                            if (has_received || completed_recv) {
                                os_unfair_lock_unlock(&state_lock);
                                return;
                            }
                            has_received = YES;
                            os_unfair_lock_unlock(&state_lock);
                            
                            if (recv_error) {
                                complete_operation(cls_dns_detector_error_timeout);
                            } else if (content) {
                                const void *data_ptr = NULL;
                                size_t size = 0;
                                dispatch_data_t contiguous = dispatch_data_create_map(content, &data_ptr, &size);
                                if (contiguous && data_ptr && size > 2) {
                                    // TCP DNS 格式：前2字节是长度
                                    uint16_t tcp_len = ntohs(*(const uint16_t *)data_ptr);
                                    // 增强验证：
                                    // 1. tcp_len必须大于0且至少为DNS头部大小
                                    // 2. tcp_len不能超过实际接收的数据长度（size - 2）
                                    // 3. tcp_len不能超过接收缓冲区大小
                                    // 4. 验证tcp_len与实际数据长度一致（TCP DNS要求长度字段必须准确）
                                    if (tcp_len > 0 && 
                                        tcp_len >= DNS_HEADER_SIZE && 
                                        tcp_len <= size - 2 && 
                                        tcp_len <= DNS_BUFFER_SIZE &&
                                        (size_t)(tcp_len + 2) <= size) { // 确保长度字段与实际数据一致
                                        // 验证实际接收的数据长度是否与tcp_len匹配
                                        if ((size_t)(tcp_len + 2) == size || size >= (size_t)(tcp_len + 2)) {
                                            memcpy(recv_buffer, (const uint8_t *)data_ptr + 2, tcp_len);
                                            *recv_len = tcp_len;
                                            ret = cls_dns_detector_error_success;
                                            *query_time_ms = (int)(now_ms() - start);
                                            // ARC模式下，dispatch_data_t会自动管理，不需要手动释放
                                            complete_operation(cls_dns_detector_error_success);
                                        } else {
                                            // 数据长度不匹配
                                            complete_operation(cls_dns_detector_error_parse_failed);
                                        }
                                    } else {
                                        // 长度验证失败
                                        complete_operation(cls_dns_detector_error_parse_failed);
                                    }
                                } else {
                                    // ARC模式下，dispatch_data_t会自动管理，不需要手动释放
                                    complete_operation(cls_dns_detector_error_parse_failed);
                                }
                            } else {
                                complete_operation(cls_dns_detector_error_timeout);
                            }
                        });
                    }
                });
            }
        } else if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
            if (!has_sent) {
                complete_operation(cls_dns_detector_error_send_failed);
            } else if (!has_received) {
                complete_operation(cls_dns_detector_error_timeout);
            }
        }
    });
    
    nw_connection_start(conn);
    
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, timeout_ms * NSEC_PER_MSEC);
    if (dispatch_semaphore_wait(sema, timeout) != 0) {
        os_unfair_lock_lock(&state_lock);
        if (!is_completed) {
            is_completed = YES;
            ret = cls_dns_detector_error_timeout;
            // 确保取消连接
            if (conn && !conn_cancelled) {
                nw_connection_cancel(conn);
                conn_cancelled = YES;
            }
        }
        os_unfair_lock_unlock(&state_lock);
    }
    
    cleanup_resources();
    
    if (ret != cls_dns_detector_error_success) {
        *recv_len = 0;
        *query_time_ms = 0;
    }
    
    return ret;
}

/**
 * 使用 Network.framework 发送 DNS 查询
 * @param payload 查询数据
 * @param payload_len 数据长度
 * @param server DNS 服务器地址
 * @param timeout_ms 超时时间（毫秒）
 * @param interface_index 网卡索引（支持绑定指定接口）
 * @param recv_buffer 接收缓冲区
 * @param recv_len 输出参数，接收长度
 * @param query_time_ms 输出参数，查询耗时
 * @return 错误码
 */
static int send_dns_with_network(const uint8_t *payload,
                                 size_t payload_len,
                                 const char *server,
                                 int timeout_ms,
                                 unsigned int interface_index,
                                 uint8_t *recv_buffer,
                                 size_t *recv_len,
                                 int *query_time_ms) {
    if (!payload || !server || !recv_buffer || !recv_len || !query_time_ms) {
        return cls_dns_detector_error_invalid_param;
    }
    
    *recv_len = 0;
    *query_time_ms = 0;
    
    __block int ret = cls_dns_detector_error_send_failed;
    __block dispatch_data_t response = NULL;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    if (!sema) {
        return cls_dns_detector_error_send_failed;
    }
    
    // 状态变量多线程访问，使用 unfair lock 保护
    __block os_unfair_lock state_lock = OS_UNFAIR_LOCK_INIT;
    __block BOOL is_completed = NO;
    __block BOOL has_sent = NO;
    __block BOOL has_received = NO;
    __block BOOL conn_cancelled = NO; // 确保仅取消一次，避免重复日志
    
    // Network.framework 资源（在 block 内修改，需要 __block）
    __block nw_endpoint_t endpoint = NULL;
    __block nw_parameters_t params = NULL;
    __block nw_protocol_stack_t protocol_stack = NULL;
    __block nw_protocol_options_t udp_options = NULL;
    __block nw_connection_t conn = NULL;
    
    // 统一清理函数，确保取消连接并断开强引用（ARC 自动管理 Network 对象内存）
    void (^cleanup_resources)(void) = ^{
        os_unfair_lock_lock(&state_lock);
        if (conn && !conn_cancelled) { 
            nw_connection_cancel(conn); 
            conn_cancelled = YES;
        }
        if (conn) {
            conn = NULL; 
        }
        os_unfair_lock_unlock(&state_lock);
        udp_options = NULL;
        protocol_stack = NULL;
        params = NULL;
        endpoint = NULL;
        response = NULL;
    };
    
    endpoint = nw_endpoint_create_host(server, "53");
    if (!endpoint) { cleanup_resources(); return cls_dns_detector_error_send_failed; }
    
    params = nw_parameters_create();
    if (!params) { cleanup_resources(); return cls_dns_detector_error_send_failed; }
    
    protocol_stack = nw_parameters_copy_default_protocol_stack(params);
    if (protocol_stack) {
        udp_options = nw_udp_create_options();
        if (udp_options) {
            nw_protocol_stack_set_transport_protocol(protocol_stack, udp_options);
        }
    }
    
    // 设置网卡绑定（如果指定了 interface_index）
    // 优先尝试通过 dlsym 动态获取 nw_interface_create_with_index（部分系统版本提供）
    // 若不可用，则回退到按接口类型的方式
    nw_interface_t required_interface = NULL;
    if (interface_index > 0) {
        if (@available(iOS 13.0, *)) {
            static nw_interface_t (*p_nw_interface_create_with_index)(uint32_t) = NULL;
            static void (*p_nw_parameters_set_required_interface)(nw_parameters_t, nw_interface_t) = NULL;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                p_nw_interface_create_with_index = (nw_interface_t (*)(uint32_t))dlsym(RTLD_DEFAULT, "nw_interface_create_with_index");
                p_nw_parameters_set_required_interface = (void (*)(nw_parameters_t, nw_interface_t))dlsym(RTLD_DEFAULT, "nw_parameters_set_required_interface");
            });
            if (p_nw_interface_create_with_index && p_nw_parameters_set_required_interface) {
                required_interface = p_nw_interface_create_with_index(interface_index);
                if (required_interface) {
                    p_nw_parameters_set_required_interface(params, required_interface);
                }
            }
        }
    }
    
    // 如果 required_interface 不可用，则回退到按接口类型的方式
    if (interface_index > 0 && required_interface == NULL) {
        BOOL interface_found = NO;
        struct ifaddrs *ifaddrs_list = NULL;
        if (getifaddrs(&ifaddrs_list) == 0) {
            for (struct ifaddrs *ifa = ifaddrs_list; ifa != NULL; ifa = ifa->ifa_next) {
                if (ifa->ifa_name && if_nametoindex(ifa->ifa_name) == interface_index) {
                    interface_found = YES;
                    // 找到匹配的接口，根据接口的实际地址类型判断
                    // 检查接口是否有 IPv4 或 IPv6 地址，以及接口标志
                    BOOL is_wifi = NO;
                    BOOL is_cellular = NO;
                    
                    // 检查接口标志
                    if (ifa->ifa_flags & IFF_UP) {
                        // 通过接口名称和地址类型判断
                        const char *if_name = ifa->ifa_name;
                        
                        // 检查是否有 IPv4 或 IPv6 地址
                        if (ifa->ifa_addr) {
                            if (ifa->ifa_addr->sa_family == AF_INET || ifa->ifa_addr->sa_family == AF_INET6) {
                                // 根据接口名称模式判断（iOS接口命名规则）
                                // en0, en1 等通常是 WiFi/以太网
                                if (strncmp(if_name, "en", 2) == 0) {
                                    // en0通常是WiFi，en1可能是其他以太网接口
                                    // 但需要进一步验证，不能仅凭名称判断
                                    // 检查接口是否不是loopback且是UP状态
                                    if (!(ifa->ifa_flags & IFF_LOOPBACK) && (ifa->ifa_flags & IFF_UP)) {
                                        is_wifi = YES;
                                    }
                                } else if (strncmp(if_name, "pdp_ip", 6) == 0) {
                                    // pdp_ip* 是蜂窝网络接口
                                    is_cellular = YES;
                                } else if (strncmp(if_name, "ipsec", 5) == 0 || 
                                          strncmp(if_name, "utun", 4) == 0) {
                                    // ipsec* 和 utun* 通常是VPN接口，归类为蜂窝网络类型
                                    // 注意：这些接口可能不是真正的蜂窝网络，但Network.framework会处理
                                    is_cellular = YES;
                                }
                                // 移除了基于interface_index范围的简单判断，因为不够准确
                            }
                        }
                    }
                    
                    // 设置接口类型
                    if (is_wifi) {
                        nw_parameters_set_required_interface_type(params, nw_interface_type_wifi);
                    } else if (is_cellular) {
                        nw_parameters_set_required_interface_type(params, nw_interface_type_cellular);
                    }
                    break;
                }
            }
            freeifaddrs(ifaddrs_list);
            if (!interface_found) {
                cleanup_resources();
                return cls_dns_detector_error_invalid_param;
            }
        } else {
            cleanup_resources();
            return cls_dns_detector_error_invalid_param;
        }
    }

    // 已设置 required_interface 后释放本地引用（parameters 会持有）
    if (required_interface) {
        required_interface = NULL;
    }
    
    conn = nw_connection_create(endpoint, params);
    if (!conn) { cleanup_resources(); return cls_dns_detector_error_send_failed; }
    
    nw_connection_set_queue(conn, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    uint64_t start = now_ms();
    
    // 安全完成操作
    void (^complete_operation)(int) = ^(int error_code) {
        os_unfair_lock_lock(&state_lock);
        if (is_completed) { os_unfair_lock_unlock(&state_lock); return; }
        is_completed = YES;
        ret = error_code;
        os_unfair_lock_unlock(&state_lock);
        dispatch_semaphore_signal(sema);
    };
    
    // UDP 发送函数
    void (^send_dns_query)(void) = ^{
        os_unfair_lock_lock(&state_lock);
        if (has_sent || is_completed) { os_unfair_lock_unlock(&state_lock); return; }
        has_sent = YES;
        os_unfair_lock_unlock(&state_lock);
        
        dispatch_data_t content = dispatch_data_create(payload, payload_len, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        nw_connection_send(conn, content, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t  _Nullable send_error) {
            os_unfair_lock_lock(&state_lock);
            BOOL completed = is_completed;
            os_unfair_lock_unlock(&state_lock);
            if (completed) return;
            
            if (send_error) {
                complete_operation(cls_dns_detector_error_send_failed);
            } else {
                nw_connection_receive_message(conn, ^(dispatch_data_t  _Nullable content, nw_content_context_t  _Nullable context, bool is_complete, nw_error_t  _Nullable recv_error) {
                    os_unfair_lock_lock(&state_lock);
                    BOOL completed_inner = is_completed;
                    if (has_received || completed_inner) {
                        os_unfair_lock_unlock(&state_lock);
                        return;
                    }
                    has_received = YES;
                    os_unfair_lock_unlock(&state_lock);
                    
                    if (recv_error) {
                        complete_operation(cls_dns_detector_error_timeout);
                    } else if (content) {
                        const void *data_ptr = NULL;
                        size_t size = 0;
                        dispatch_data_t contiguous = dispatch_data_create_map(content, &data_ptr, &size);
                        if (contiguous && data_ptr && size > 0) {
                            // 如果响应超过缓冲区，视为解析失败，避免无声截断
                            if (size > DNS_BUFFER_SIZE) {
                                complete_operation(cls_dns_detector_error_parse_failed);
                            } else {
                                memcpy(recv_buffer, data_ptr, size);
                                *recv_len = size;
                                ret = cls_dns_detector_error_success;
                                *query_time_ms = (int)(now_ms() - start);
                                response = NULL;
                                // ARC模式下，dispatch_data_t会自动管理，不需要手动释放
                                complete_operation(cls_dns_detector_error_success);
                            }
                        } else {
                            // ARC模式下，dispatch_data_t会自动管理，不需要手动释放
                            complete_operation(cls_dns_detector_error_parse_failed);
                        }
                    } else {
                        complete_operation(cls_dns_detector_error_timeout);
                    }
                });
            }
        });
    };
    
    // UDP 连接状态处理
    nw_connection_set_state_changed_handler(conn, ^(nw_connection_state_t state, nw_error_t  _Nullable error) {
        os_unfair_lock_lock(&state_lock);
        BOOL completed = is_completed;
        BOOL sent = has_sent;
        BOOL received = has_received;
        os_unfair_lock_unlock(&state_lock);
        if (completed) return;
        
        if (state == nw_connection_state_ready) {
            // 只在ready状态且未发送时发送，避免重复发送
            if (!sent) send_dns_query();
        } else if (state == nw_connection_state_waiting) {
            // 移除waiting状态的发送逻辑，避免重复发送
            // waiting状态通常表示连接正在建立，应该等待ready状态
        } else if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
            if (!sent) {
                complete_operation(cls_dns_detector_error_send_failed);
            } else if (!received) {
                complete_operation(cls_dns_detector_error_timeout);
            }
        }
        // 移除invalid状态的发送逻辑，避免重复发送
    });
    
    nw_connection_start(conn);
    
    // UDP 无连接，启动后尝试快速发送（仅在ready状态时）
    // 注意：由于UDP是无连接的，可能不会进入ready状态，所以保留这个延迟发送
    // 但增加更严格的检查避免重复发送
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.005 * NSEC_PER_SEC)), 
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        os_unfair_lock_lock(&state_lock);
        BOOL done = is_completed;
        BOOL already_sent = has_sent;
        os_unfair_lock_unlock(&state_lock);
        if (!already_sent && !done) {
            send_dns_query();
        }
    });
    
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, timeout_ms * NSEC_PER_MSEC);
    if (dispatch_semaphore_wait(sema, timeout) != 0) {
        os_unfair_lock_lock(&state_lock);
        if (!is_completed) {
            is_completed = YES;
            ret = cls_dns_detector_error_timeout;
            // 确保取消连接
            if (conn && !conn_cancelled) {
                nw_connection_cancel(conn);
                conn_cancelled = YES;
            }
        }
        os_unfair_lock_unlock(&state_lock);
    }
    
    // 取消并释放资源
    cleanup_resources();
    
    if (ret != cls_dns_detector_error_success) {
        *recv_len = 0;
        *query_time_ms = 0;
    }
    
    return ret;
}

#define DNS_MAX_SERVER_COUNT 64

/**
 * 计算以 NULL 结尾的 DNS 服务器数组长度
 * @param dns_servers DNS 服务器数组（必须以 NULL 结尾）
 * @return 实际长度，如果数组不是以 NULL 结尾则返回 0
 */
static size_t calculate_dns_server_count(const char *const *dns_servers) {
    if (!dns_servers) return 0;
    
    size_t count = 0;
    // 遍历直到遇到 NULL 或达到合理上限（防止无限循环）
    while (count < DNS_MAX_SERVER_COUNT && dns_servers[count] != NULL) {
        count++;
    }
    
    // 如果达到上限且最后一个元素不是 NULL，说明数组可能不是以 NULL 结尾的
    // 返回 0 表示无法自动计算，需要手动指定
    if (count >= DNS_MAX_SERVER_COUNT && dns_servers[count] != NULL) {
        return 0;
    }
    
    return count;
}

/**
 * 验证 DNS 服务器地址格式（IPv4 或 IPv6）
 * @param server 服务器地址
 * @return 1=IPv6, 0=IPv4, -1=无效地址
 */
static int validate_dns_server_address(const char *server) {
    if (!server || server[0] == '\0') return -1;
    
    // 检查地址长度（IPv4最长15字符，IPv6最长45字符）
    size_t len = strlen(server);
    if (len == 0 || len > 45) return -1;  // 45是IPv6的最大长度
    
    // 尝试解析为 IPv4
    struct in_addr addr4;
    if (inet_pton(AF_INET, server, &addr4) == 1) {
        // 额外验证：检查是否为有效的单播地址（排除0.0.0.0和广播地址）
        // 注意：某些系统可能使用0.0.0.0作为占位符，这里允许但记录
        return 0; // IPv4
    }
    
    // 尝试解析为 IPv6
    struct in6_addr addr6;
    if (inet_pton(AF_INET6, server, &addr6) == 1) {
        // 额外验证：检查是否为有效的单播地址（排除::和::1）
        // 注意：这里允许所有有效的IPv6地址格式
        return 1; // IPv6
    }
    
    return -1; // 无效地址
}

/**
 * 根据 prefer 参数判断服务器类型是否匹配
 * @param prefer IP 版本偏好：0=IPv4优先, 1=IPv6优先, 2=IPv4 only, 3=IPv6 only
 * @param server_type 服务器类型：0=IPv4, 1=IPv6
 * @return 1=匹配, 0=不匹配
 */
static int is_server_type_matched(int prefer, int server_type) {
    if (prefer == 2) {
        // IPv4 only: 只接受 IPv4
        return (server_type == 0) ? 1 : 0;
    } else if (prefer == 3) {
        // IPv6 only: 只接受 IPv6
        return (server_type == 1) ? 1 : 0;
    } else {
        // prefer == 0 或 1: 接受 IPv4 和 IPv6
        return 1;
    }
}

// IPv6 可用性缓存（使用静态变量和锁确保线程安全，支持刷新）
static int g_ipv6_available_cached = -1;  // -1 表示未初始化
static uint64_t g_ipv6_check_timestamp = 0;  // 上次检查的时间戳（毫秒）
static os_unfair_lock g_ipv6_check_lock = OS_UNFAIR_LOCK_INIT;
#define IPv6_CACHE_TTL_MS 30000  // 缓存有效期30秒

/**
 * 检查系统是否有可用的 IPv6 路由
 * 通过检查是否有非链路本地的 IPv6 地址来判断
 * 使用缓存机制避免重复检测，但支持定期刷新
 * @return 1=IPv6可用, 0=IPv6不可用
 */
static int is_ipv6_available(void) {
    uint64_t now = now_ms();
    
    // 双重检查锁定模式：先快速检查缓存（无锁）
    int cached_value = g_ipv6_available_cached;
    uint64_t cached_timestamp = g_ipv6_check_timestamp;
    
    // 如果缓存有效，直接返回
    if (cached_value != -1 && (now - cached_timestamp) <= IPv6_CACHE_TTL_MS) {
        return cached_value;
    }
    
    // 缓存无效，需要重新检查（加锁）
    os_unfair_lock_lock(&g_ipv6_check_lock);
    
    // 再次检查（双重检查），可能在等待锁的过程中其他线程已经更新了缓存
    if (g_ipv6_available_cached != -1 && 
        (now - g_ipv6_check_timestamp) <= IPv6_CACHE_TTL_MS) {
        int result = g_ipv6_available_cached;
        os_unfair_lock_unlock(&g_ipv6_check_lock);
        return result;
    }
    
    // 需要重新检查，更新时间戳防止其他线程重复检查
    g_ipv6_check_timestamp = now;
    os_unfair_lock_unlock(&g_ipv6_check_lock);
    
    // 执行实际的检查（在锁外，避免长时间持锁）
    struct ifaddrs *ifaddrs_list = NULL;
    int has_global_ipv6 = 0;
    
    if (getifaddrs(&ifaddrs_list) == 0) {
        for (struct ifaddrs *ifa = ifaddrs_list; ifa != NULL; ifa = ifa->ifa_next) {
            if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET6) {
                continue;
            }
            
            // 检查接口是否 UP 且 RUNNING，且非 loopback
            if ((ifa->ifa_flags & IFF_UP) == 0 || 
                (ifa->ifa_flags & IFF_RUNNING) == 0 || 
                (ifa->ifa_flags & IFF_LOOPBACK)) {
                continue;
            }
            
            struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)ifa->ifa_addr;
            const uint8_t *bytes = (const uint8_t *)&addr6->sin6_addr;
            
            // 检查是否是全局单播地址（2000::/3）或唯一本地地址（fc00::/7）
            // 排除链路本地地址（fe80::/10）和环回地址（::1）
            if (bytes[0] == 0x20 || bytes[0] == 0x21 || bytes[0] == 0x22 || bytes[0] == 0x23 || // 2000::/4
                bytes[0] == 0x24 || bytes[0] == 0x25 || bytes[0] == 0x26 || bytes[0] == 0x27 || // 2000::/4
                bytes[0] == 0x28 || bytes[0] == 0x29 || bytes[0] == 0x2a || bytes[0] == 0x2b || // 2000::/4
                bytes[0] == 0x2c || bytes[0] == 0x2d || bytes[0] == 0x2e || bytes[0] == 0x2f || // 2000::/4
                (bytes[0] == 0xfc || bytes[0] == 0xfd)) { // fc00::/7 (唯一本地地址)
                has_global_ipv6 = 1;
                break;
            }
        }
        
        freeifaddrs(ifaddrs_list);
    }
    
    // 更新缓存（加锁）
    os_unfair_lock_lock(&g_ipv6_check_lock);
    g_ipv6_available_cached = has_global_ipv6;
    g_ipv6_check_timestamp = now;
    os_unfair_lock_unlock(&g_ipv6_check_lock);
    
    return has_global_ipv6;
}

// DNS 服务器列表常量
#define DNS_MAX_DEFAULT_SERVERS 4
static const char *DNS_IPV4_SERVERS[] = {"119.29.29.29", "182.254.116.116", "119.28.28.28", "182.254.118.118"};
static const char *DNS_IPV6_SERVERS[] = {"2001:4860:4860::8888", "240e:4c:4008::1", "2408:8899::8", "2409:8088::a"};

/**
 * 获取默认 DNS 服务器
 * @param index 服务器索引 (0-3)
 * @param prefer_ipv6 是否偏好 IPv6
 * @return DNS 服务器地址，失败返回 NULL
 */
static const char *get_default_server(int index, int prefer_ipv6) {
    if (index < 0 || index >= DNS_MAX_DEFAULT_SERVERS) return NULL;
    return prefer_ipv6 ? DNS_IPV6_SERVERS[index] : DNS_IPV4_SERVERS[index];
}

/**
 * 根据 prefer 参数填充默认 DNS 服务器候选列表
 * @param candidates 输出数组，最多填充 8 个服务器
 * @param candidate_count 输出参数，实际填充的数量
 * @param prefer IP 版本偏好：0=IPv4优先, 1=IPv6优先, 2=IPv4 only, 3=IPv6 only
 */
static void fill_default_dns_candidates(const char *candidates[8], size_t *candidate_count, int prefer) {
    *candidate_count = 0;
    
    // 检查 IPv6 是否可用
    int ipv6_available = is_ipv6_available();
    
    if (prefer == 2) {
        // IPv4 only: 只使用 IPv4 DNS 服务器
        for (int i = 0; i < DNS_MAX_DEFAULT_SERVERS && *candidate_count < 8; i++) {
            const char *server = get_default_server(i, 0);
            if (server) candidates[(*candidate_count)++] = server;
        }
    } else if (prefer == 3) {
        // IPv6 only: 只使用 IPv6 DNS 服务器（如果 IPv6 不可用，返回空列表）
        if (ipv6_available) {
            for (int i = 0; i < DNS_MAX_DEFAULT_SERVERS && *candidate_count < 8; i++) {
                const char *server = get_default_server(i, 1);
                if (server) candidates[(*candidate_count)++] = server;
            }
        }
    } else if (prefer == 1) {
        // IPv6 优先：先添加 IPv6 服务器，再添加 IPv4 服务器
        if (ipv6_available) {
            for (int i = 0; i < DNS_MAX_DEFAULT_SERVERS && *candidate_count < 8; i++) {
                const char *server = get_default_server(i, 1);
                if (server) candidates[(*candidate_count)++] = server;
            }
        }
        for (int i = 0; i < DNS_MAX_DEFAULT_SERVERS && *candidate_count < 8; i++) {
            const char *server = get_default_server(i, 0);
            if (server) candidates[(*candidate_count)++] = server;
        }
    } else {
        // IPv4 优先（默认）：先添加 IPv4 服务器，再添加 IPv6 服务器
        for (int i = 0; i < DNS_MAX_DEFAULT_SERVERS && *candidate_count < 8; i++) {
            const char *server = get_default_server(i, 0);
            if (server) candidates[(*candidate_count)++] = server;
        }
        if (ipv6_available) {
            for (int i = 0; i < DNS_MAX_DEFAULT_SERVERS && *candidate_count < 8; i++) {
                const char *server = get_default_server(i, 1);
                if (server) candidates[(*candidate_count)++] = server;
            }
        }
    }
}

/**
 * 构建 DNS 服务器候选列表
 * @param dns_servers 用户指定的 DNS 服务器列表（可以为 NULL）
 * @param dns_server_count DNS 服务器数量（如果为 0，将自动计算）
 * @param prefer IP 版本偏好
 * @param candidates 输出数组，最多填充 8 个服务器
 * @param candidate_count 输出参数，实际填充的数量
 * @param dns_source 输出参数，DNS 来源（"specified" 或 "public"）
 * @return 0=成功, 负数=错误码（如无有效服务器）
 */
static int build_dns_candidate_list(const char *const *dns_servers,
                                     size_t dns_server_count,
                                     int prefer,
                                     const char *candidates[8],
                                     size_t *candidate_count,
                                     char *dns_source) {
    *candidate_count = 0;
    
    // 自动计算 DNS 服务器数组长度（数组必须以 NULL 结尾）
    size_t actual_dns_server_count = dns_server_count;
    if (dns_servers && dns_server_count == 0) {
        actual_dns_server_count = calculate_dns_server_count(dns_servers);
    }
    
    // 如果用户指定了服务器，验证并过滤
    if (dns_servers && actual_dns_server_count > 0) {
        // 检查 IPv6 是否可用
        int ipv6_available = is_ipv6_available();
        
        for (size_t i = 0; i < actual_dns_server_count && *candidate_count < 8; i++) {
            const char *server = dns_servers[i];
            if (!server || server[0] == '\0') continue;
            
            // 验证地址格式
            int server_type = validate_dns_server_address(server);
            if (server_type < 0) continue; // 无效地址，跳过
            
            // 如果服务器是 IPv6 但系统不支持 IPv6，跳过
            if (server_type == 1 && !ipv6_available) continue;
            
            // 根据 prefer 过滤
            if (!is_server_type_matched(prefer, server_type)) continue; // 类型不匹配，跳过
            
            candidates[(*candidate_count)++] = server;
        }
        
        if (*candidate_count > 0) {
            strncpy(dns_source, "specified", sizeof(dns_source) - 1);
            dns_source[sizeof(dns_source) - 1] = '\0';
            return cls_dns_detector_error_success;
        }
    }
    
    // 用户未指定服务器，或所有指定服务器都无效，使用默认公共 DNS
    fill_default_dns_candidates((const char **)candidates, candidate_count, prefer);
    if (*candidate_count > 0) {
        strncpy(dns_source, "public", sizeof(dns_source) - 1);
        dns_source[sizeof(dns_source) - 1] = '\0';
        return cls_dns_detector_error_success;
    }
    
    return cls_dns_detector_error_no_valid_server; // 无有效服务器（例如 prefer=IPv6 only 但系统无 IPv6）
}

// 并发查询结果结构
typedef struct {
    const char *server;
    uint8_t recv_buffer[DNS_BUFFER_SIZE];
    size_t recv_len;
    int query_time_ms;
    int error_code;
    BOOL completed;
    BOOL cancelled;  // 标记是否已取消
} ConcurrentQueryResult;

/**
 * 执行单个 DNS 查询（用于并发查询）
 * @param send_buffer 发送缓冲区
 * @param send_len 发送长度
 * @param server DNS 服务器地址
 * @param quick_timeout_ms 快速超时时间（毫秒）
 * @param full_timeout_ms 完整超时时间（毫秒）
 * @param interface_index 网卡索引
 * @param result 输出结果
 * @return 错误码
 */
static int perform_single_dns_query(const uint8_t *send_buffer,
                                    size_t send_len,
                                    const char *server,
                                    int quick_timeout_ms,
                                    int full_timeout_ms,
                                    unsigned int interface_index,
                                    ConcurrentQueryResult *result,
                                    atomic_bool *should_cancel) {
    if (!send_buffer || !server || !result) return cls_dns_detector_error_invalid_param;
    
    result->server = server;
    result->completed = NO;
    result->cancelled = NO;
    result->error_code = cls_dns_detector_error_send_failed;
    result->recv_len = 0;
    result->query_time_ms = 0;
    
    // 检查是否应该取消
    if (should_cancel && atomic_load_explicit(should_cancel, memory_order_relaxed)) {
        result->cancelled = YES;
        result->completed = YES;
        return cls_dns_detector_error_send_failed;
    }
    
    // 先尝试快速查询
    int quick_result = send_dns_with_network(send_buffer, send_len, server, quick_timeout_ms,
                                             interface_index, result->recv_buffer, &result->recv_len,
                                             &result->query_time_ms);
    
    // 检查是否在查询过程中被取消
    if (should_cancel && atomic_load_explicit(should_cancel, memory_order_relaxed)) {
        result->cancelled = YES;
        result->completed = YES;
        return cls_dns_detector_error_send_failed;
    }
    
    if (quick_result == cls_dns_detector_error_success && result->recv_len > 0) {
        result->error_code = cls_dns_detector_error_success;
        result->completed = YES;
        return cls_dns_detector_error_success;
    }
    
    // 快速查询超时，尝试完整超时查询
    if (quick_result == cls_dns_detector_error_timeout && full_timeout_ms > quick_timeout_ms) {
        // 再次检查是否应该取消
        if (should_cancel && atomic_load_explicit(should_cancel, memory_order_relaxed)) {
            result->cancelled = YES;
            result->completed = YES;
            return cls_dns_detector_error_send_failed;
        }
        
        quick_result = send_dns_with_network(send_buffer, send_len, server, full_timeout_ms,
                                            interface_index, result->recv_buffer, &result->recv_len,
                                            &result->query_time_ms);
        
        // 最终检查是否被取消
        if (should_cancel && atomic_load_explicit(should_cancel, memory_order_relaxed)) {
            result->cancelled = YES;
            result->completed = YES;
            return cls_dns_detector_error_send_failed;
        }
    }
    
    result->error_code = quick_result;
    result->completed = YES;
    
    if (quick_result == cls_dns_detector_error_success && result->recv_len > 0) {
        return cls_dns_detector_error_success;
    }
    
    return quick_result;
}

/**
 * 并发查询多个 DNS 服务器，返回最快成功的响应
 * @param send_buffer 发送缓冲区
 * @param send_len 发送长度
 * @param candidates DNS 服务器候选列表
 * @param candidate_count 候选数量
 * @param timeout_ms 超时时间（毫秒）
 * @param interface_index 网卡索引
 * @param recv_buffer 接收缓冲区
 * @param recv_len 输出参数，接收长度
 * @param query_time_ms 输出参数，查询耗时
 * @param success_server 输出参数，成功的服务器地址
 * @return 错误码
 */
static int perform_concurrent_dns_queries(const uint8_t *send_buffer,
                                         size_t send_len,
                                         const char *candidates[8],
                                         size_t candidate_count,
                                         int timeout_ms,
                                         unsigned int interface_index,
                                         uint8_t *recv_buffer,
                                         size_t *recv_len,
                                         int *query_time_ms,
                                         const char **success_server) {
    if (candidate_count == 0 || !candidates || !send_buffer || !recv_buffer) {
        return cls_dns_detector_error_invalid_param;
    }
    
    // 单个服务器，直接查询
    if (candidate_count == 1) {
        ConcurrentQueryResult result;
        atomic_bool dummy_cancel = false;
        int ret = perform_single_dns_query(send_buffer, send_len, candidates[0],
                                           timeout_ms, timeout_ms, interface_index, &result, &dummy_cancel);
        if (ret == cls_dns_detector_error_success) {
            memcpy(recv_buffer, result.recv_buffer, result.recv_len);
            *recv_len = result.recv_len;
            *query_time_ms = result.query_time_ms;
            *success_server = result.server;
        }
        return ret;
    }
    
    // 多个服务器，并发查询
    ConcurrentQueryResult *results = calloc(candidate_count, sizeof(ConcurrentQueryResult));
    if (!results) {
        return cls_dns_detector_error_send_failed;
    }
    
    // 初始化结果数组
    for (size_t i = 0; i < candidate_count; i++) {
        memset(&results[i], 0, sizeof(ConcurrentQueryResult));
        results[i].server = candidates[i];
        results[i].completed = NO;
        results[i].cancelled = NO;
        results[i].error_code = cls_dns_detector_error_send_failed;
        results[i].recv_len = 0;
        results[i].query_time_ms = 0;
    }
    
    dispatch_group_t group = dispatch_group_create();
    if (!group) {
        free(results);
        return cls_dns_detector_error_send_failed;
    }
    
    dispatch_semaphore_t first_success_sema = dispatch_semaphore_create(0);
    if (!first_success_sema) {
        free(results);
        // 在ARC环境下，dispatch对象会自动管理，不需要手动release
        return cls_dns_detector_error_send_failed;
    }
    
    dispatch_semaphore_t success_lock = dispatch_semaphore_create(1);
    if (!success_lock) {
        free(results);
        // 在ARC环境下，dispatch对象会自动管理，不需要手动release
        return cls_dns_detector_error_send_failed;
    }
    
    // 使用结构体存储成功结果，确保原子性
    typedef struct {
        BOOL has_success;
        const char *server;
        size_t recv_len;
        int query_time_ms;
        size_t result_index;  // 对应的results数组索引
    } SuccessResult;
    
    __block SuccessResult success_result = {NO, NULL, 0, 0, SIZE_MAX};
    __block atomic_bool should_cancel_all = false;  // 取消标志（原子避免竞争）
    
    // 快速失败时间：使用较短超时进行快速检测（1秒）
    int quick_timeout_ms = (timeout_ms > 1000) ? 1000 : timeout_ms;
    
    for (size_t i = 0; i < candidate_count; i++) {
        size_t idx = i;
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            // 如果已有成功结果，跳过剩余查询以加快返回
            dispatch_semaphore_wait(success_lock, DISPATCH_TIME_FOREVER);
            BOOL should_skip = success_result.has_success || atomic_load_explicit(&should_cancel_all, memory_order_relaxed);
            dispatch_semaphore_signal(success_lock);
            if (should_skip) {
                // 标记为已取消
                results[idx].completed = YES;
                results[idx].cancelled = YES;
                results[idx].error_code = cls_dns_detector_error_send_failed;
                dispatch_group_leave(group);
                return;
            }

            // 执行查询，传入取消标志
            perform_single_dns_query(send_buffer, send_len, candidates[idx],
                                    quick_timeout_ms, timeout_ms, interface_index,
                                    &results[idx], &should_cancel_all);
            
            // 再次检查是否已有成功结果（可能在查询过程中其他查询已成功）
            dispatch_semaphore_wait(success_lock, DISPATCH_TIME_FOREVER);
            BOOL already_success = success_result.has_success;
            // 使用原子性检查：只有在没有成功结果且当前查询成功时才设置
            if (!already_success && !results[idx].cancelled && 
                results[idx].error_code == cls_dns_detector_error_success && 
                results[idx].recv_len > 0 && results[idx].recv_len <= DNS_BUFFER_SIZE) {
                success_result.has_success = YES;
                success_result.server = results[idx].server;
                success_result.recv_len = results[idx].recv_len;
                success_result.query_time_ms = results[idx].query_time_ms;
                success_result.result_index = idx;
                // 设置取消标志，让其他查询尽快退出
                atomic_store_explicit(&should_cancel_all, true, memory_order_relaxed);
                dispatch_semaphore_signal(first_success_sema);
            }
            dispatch_semaphore_signal(success_lock);
            
            dispatch_group_leave(group);
        });
    }
    
    // 等待第一个成功响应或超时
    dispatch_time_t wait_time = dispatch_time(DISPATCH_TIME_NOW, timeout_ms * NSEC_PER_MSEC);
    int send_result = cls_dns_detector_error_send_failed;
    
    if (dispatch_semaphore_wait(first_success_sema, wait_time) == 0) {
        // 收到成功响应，在锁保护下读取共享数据，确保数据一致性
        dispatch_semaphore_wait(success_lock, DISPATCH_TIME_FOREVER);
        
        // 在锁保护下读取成功结果，直接使用result_index避免查找
        BOOL found = NO;
        if (success_result.has_success && success_result.result_index < candidate_count) {
            size_t idx = success_result.result_index;
            // 再次验证结果有效性，确保数据已写入且有效
            if (results[idx].completed && 
                results[idx].error_code == cls_dns_detector_error_success &&
                results[idx].recv_len > 0 && 
                results[idx].recv_len <= DNS_BUFFER_SIZE &&
                results[idx].server == success_result.server) {
                // 使用实际结果中的数据
                size_t actual_recv_len = results[idx].recv_len;
                int actual_query_time_ms = results[idx].query_time_ms;
                memcpy(recv_buffer, results[idx].recv_buffer, actual_recv_len);
                *success_server = success_result.server;
                *recv_len = actual_recv_len;
                *query_time_ms = actual_query_time_ms;
                send_result = cls_dns_detector_error_success;
                found = YES;
            }
        }
        dispatch_semaphore_signal(success_lock);
        
        if (!found) {
            // 如果找不到有效结果，继续等待其他查询完成
            send_result = cls_dns_detector_error_send_failed;
        }
        
        // 等待所有任务完成后再释放内存（使用较短的超时，避免无限等待）
        dispatch_time_t short_timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC));
        dispatch_group_wait(group, short_timeout);
        
    } else {
        // 等待所有查询完成，选择最快的成功响应
        // 简化超时计算：使用固定等待时间，避免复杂的剩余时间计算
        // 由于已经等待了timeout_ms，这里只等待一个较短的时间让其他查询完成
        dispatch_time_t remaining_timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC));
        dispatch_group_wait(group, remaining_timeout);
        
        // 在锁保护下查找最快的结果，确保数据一致性
        dispatch_semaphore_wait(success_lock, DISPATCH_TIME_FOREVER);
        
        int fastest_time = INT_MAX;
        int fastest_index = -1;
        for (size_t i = 0; i < candidate_count; i++) {
            // 确保结果已完成且有效
            if (results[i].completed &&
                results[i].error_code == cls_dns_detector_error_success &&
                results[i].recv_len > 0 &&
                results[i].recv_len <= DNS_BUFFER_SIZE &&
                results[i].query_time_ms < fastest_time) {
                fastest_time = results[i].query_time_ms;
                fastest_index = (int)i;
            }
        }
        
        if (fastest_index >= 0) {
            send_result = cls_dns_detector_error_success;
            *success_server = results[fastest_index].server;
            *recv_len = results[fastest_index].recv_len;
            *query_time_ms = results[fastest_index].query_time_ms;
            memcpy(recv_buffer, results[fastest_index].recv_buffer, results[fastest_index].recv_len);
        } else {
            // 所有查询都失败，返回第一个错误码
            send_result = (candidate_count > 0) ? results[0].error_code : cls_dns_detector_error_send_failed;
        }
        dispatch_semaphore_signal(success_lock);
        
        // 确保所有任务都已完成后再释放内存
        // 使用较短的超时时间，避免无限等待
        dispatch_time_t final_wait = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC));
        dispatch_group_wait(group, final_wait);
    }
    
    // 注意：在ARC环境下，dispatch对象会自动管理，不需要手动release
    // 所有任务已完成，安全释放内存
    free(results);
    
    return send_result;
}

int cls_dns_detector_perform(const char *domain,
                             const char *const _Nullable * _Nullable dns_servers,
                             size_t dns_server_count,
                             int prefer,
                             int timeout_ms,
                             char *json_buffer,
                             size_t buffer_size) {
    if (!domain || !json_buffer || buffer_size == 0) return cls_dns_detector_error_invalid_param;
    json_buffer[0] = '\0';
    if (prefer < 0 || prefer > 3) prefer = 0;
    if (timeout_ms <= 0) timeout_ms = DNS_DEFAULT_TIMEOUT_MS;
    if (timeout_ms < DNS_MIN_TIMEOUT_MS) timeout_ms = DNS_MIN_TIMEOUT_MS;
    if (timeout_ms > DNS_MAX_TIMEOUT_MS) timeout_ms = DNS_MAX_TIMEOUT_MS;
    uint8_t send_buffer[DNS_BUFFER_SIZE] = {0};
    uint8_t recv_buffer[DNS_BUFFER_SIZE] = {0};
    // 生成1到65535之间的查询ID（0可能在某些实现中被视为无效）
    // 使用更随机的方法避免在同一秒内多次查询生成相同ID
    static atomic_int query_id_counter = 0;
    uint16_t random_part = (uint16_t)(arc4random_uniform(UINT16_MAX - 1) + 1);
    int32_t counter_part = atomic_fetch_add_explicit(&query_id_counter, 1, memory_order_relaxed) + 1;
    // 使用更简单的组合方式，避免取模导致的分布不均
    int query_id = (int)((random_part + (uint16_t)counter_part) % UINT16_MAX + 1);
    int send_len = build_dns_query(domain, send_buffer, sizeof(send_buffer), (uint16_t)query_id, prefer);
    if (send_len <= 0) {
        return cls_dns_detector_error_build_query_failed;
    }
    
    // 构建 DNS 服务器候选列表
    const char *candidates[8] = {0};
    size_t candidate_count = 0;
    char dns_source[32] = {0};
    
    if (build_dns_candidate_list(dns_servers, dns_server_count, prefer, candidates,
                                 &candidate_count, dns_source) != 0) {
        return cls_dns_detector_error_invalid_param;
    }
    
    // 顺序查询服务器（旧版本兼容，不使用并发）
    const char *server = NULL;
    size_t recv_len = 0;
    int query_time_ms = 0;
    int send_result = cls_dns_detector_error_send_failed;
    
    for (size_t i = 0; i < candidate_count; i++) {
        server = candidates[i];
        recv_len = 0;
        query_time_ms = 0;
        send_result = send_dns_with_network(send_buffer, (size_t)send_len, server, timeout_ms, 0,
                                           recv_buffer, &recv_len, &query_time_ms);
        if (send_result == cls_dns_detector_error_success && recv_len > 0) {
            break;
        }
    }
    
    if (send_result != cls_dns_detector_error_success) {
        return send_result;
    }
    
    // 解析 DNS 响应
    tiny_dns_header header = {0};
    if (parse_dns_header(recv_buffer, recv_len, &header) != 0) {
        return cls_dns_detector_error_parse_failed;
    }
    
    // 校验 Query ID 是否匹配，防止接受过期或伪造的响应
    if (header.id != (uint16_t)query_id) {
        return cls_dns_detector_error_parse_failed;
    }
    
    // 检测 TC (Truncated) 标志，如果设置了则使用 TCP 重试
    BOOL is_truncated = (header.flags & 0x0200) != 0;
    if (is_truncated && server) {
        // 使用 TCP 重试查询以获取完整响应
        size_t tcp_recv_len = 0;
        int tcp_query_time_ms = 0;
        int tcp_result = send_dns_with_network_tcp(send_buffer, (size_t)send_len, server, timeout_ms,
                                                   0, recv_buffer, &tcp_recv_len, &tcp_query_time_ms);
        if (tcp_result == cls_dns_detector_error_success && tcp_recv_len > 0) {
            recv_len = tcp_recv_len;
            query_time_ms = tcp_query_time_ms;
            
            // 重新解析 TCP 响应
            if (parse_dns_header(recv_buffer, recv_len, &header) != 0) {
                return cls_dns_detector_error_parse_failed;
            }
            if (header.id != (uint16_t)query_id) {
                return cls_dns_detector_error_parse_failed;
            }
            // TCP 响应不应该有 TC 标志
            is_truncated = NO;
        } else {
            // TCP 查询失败，如果 UDP 响应被截断，返回错误而不是使用不完整的数据
            if (is_truncated) {
                return cls_dns_detector_error_parse_failed;
            }
        }
    }
    
    // 校验问题节是否与请求匹配
    uint16_t expected_qtype = (prefer == 1 || prefer == 3) ? 28 : 1;
    if (validate_dns_question_section(recv_buffer, recv_len, &header, domain, expected_qtype) != 0) {
        return cls_dns_detector_error_parse_failed;
    }
    
    // 解析答案记录（只包括 ANSWER 和 ADDITIONAL，不包括 AUTHORITY）
    DnsAnswerRecordArray answers;
    dns_answer_record_array_init(&answers);
    
    int parse_ret = dns_detector_parse_answers(recv_buffer, recv_len, &header, &answers);
    if (parse_ret != 0) {
        dns_answer_record_array_free(&answers);
        return cls_dns_detector_error_parse_failed;
    }
    
    // 生成 JSON
    int json_ret = dns_result_to_json(domain, server, &header, &answers, recv_len, prefer, 
                                     query_time_ms, json_buffer, buffer_size);
    dns_answer_record_array_free(&answers);
    
    if (json_ret < 0) {
        return cls_dns_detector_error_json_failed;
    }
    
    return cls_dns_detector_error_success;
}

/**
 * 将 DNS 响应码转换为字符串
 * @param rcode DNS 响应码
 * @return 状态字符串
 */
static const char *get_status_string(uint8_t rcode) {
    switch (rcode) {
        case 0: return "NOERROR";   // 无错误
        case 1: return "FORMERR";    // 格式错误
        case 2: return "SERVFAIL";   // 服务器失败
        case 3: return "NXDOMAIN";  // 域名不存在
        case 4: return "NOTIMP";     // 未实现
        case 5: return "REFUSED";    // 拒绝
        default: return "UNKNOWN";   // 未知
    }
}

/**
 * 构建 DNS 标志位字符串
 * @param flags DNS 标志位
 * @param flags_str 输出缓冲区
 * @param flags_size 缓冲区大小
 */
static void build_flags_string(uint16_t flags, char *flags_str, size_t flags_size) {
    if (!flags_str || flags_size == 0) return;
    
    flags_str[0] = '\0';
    size_t pos = 0;
    int flag_count = 0;
    
    // QR (Query Response) - 查询/响应标志
    if (flags & 0x8000) {
        if (flag_count > 0 && pos + 3 < flags_size) flags_str[pos++] = ' ';
        if (pos + 2 < flags_size) {
            flags_str[pos++] = 'q';
            flags_str[pos++] = 'r';
            flag_count++;
        }
    }
    // AA (Authoritative Answer) - 权威答案
    if (flags & 0x0400) {
        if (flag_count > 0 && pos + 3 < flags_size) flags_str[pos++] = ' ';
        if (pos + 2 < flags_size) {
            flags_str[pos++] = 'a';
            flags_str[pos++] = 'a';
            flag_count++;
        }
    }
    // TC (Truncated) - 截断标志
    if (flags & 0x0200) {
        if (flag_count > 0 && pos + 3 < flags_size) flags_str[pos++] = ' ';
        if (pos + 2 < flags_size) {
            flags_str[pos++] = 't';
            flags_str[pos++] = 'c';
            flag_count++;
        }
    }
    // RD (Recursion Desired) - 期望递归
    if (flags & 0x0100) {
        if (flag_count > 0 && pos + 3 < flags_size) flags_str[pos++] = ' ';
        if (pos + 2 < flags_size) {
            flags_str[pos++] = 'r';
            flags_str[pos++] = 'd';
            flag_count++;
        }
    }
    // RA (Recursion Available) - 递归可用
    if (flags & 0x0080) {
        if (flag_count > 0 && pos + 3 < flags_size) flags_str[pos++] = ' ';
        if (pos + 2 < flags_size) {
            flags_str[pos++] = 'r';
            flags_str[pos++] = 'a';
            flag_count++;
        }
    }
    
    if (flag_count == 0 && pos + 5 < flags_size) {
        strcpy(flags_str, "none");
    } else {
        flags_str[pos] = '\0';
    }
}

// 单次 DNS 查询（指定 prefer）
static cls_dns_detector_error_code perform_dns_with_prefer(const char *domain,
                                                           const char *const *dns_servers,
                                                           size_t dns_server_count,
                                                           int prefer,
                                                           int timeout_ms,
                                                           unsigned int interface_index,
                                                           cls_dns_detector_result *result) {
    if (!domain || !result) return cls_dns_detector_error_invalid_param;
    if (prefer < 0 || prefer > 3) return cls_dns_detector_error_invalid_param;
    if (validate_interface_index(interface_index) < 0) return cls_dns_detector_error_invalid_param;
    
    // 初始化结果结构
    memset(result, 0, sizeof(cls_dns_detector_result));
    strncpy(result->domain, domain, sizeof(result->domain) - 1);
    result->domain[sizeof(result->domain) - 1] = '\0';
    strncpy(result->method, "dns", sizeof(result->method) - 1);
    result->method[sizeof(result->method) - 1] = '\0';
    result->prefer = prefer;
    
    // 构建 DNS 查询
    uint8_t send_buffer[DNS_BUFFER_SIZE] = {0};
    uint8_t recv_buffer[DNS_BUFFER_SIZE] = {0};
    // 生成1到65535之间的查询ID（0可能在某些实现中被视为无效）
    // 使用更随机的方法避免在同一秒内多次查询生成相同ID
    static atomic_int query_id_counter = 0;
    uint16_t random_part = (uint16_t)(arc4random_uniform(UINT16_MAX - 1) + 1);
    int32_t counter_part = atomic_fetch_add_explicit(&query_id_counter, 1, memory_order_relaxed) + 1;
    // 使用更简单的组合方式，避免取模导致的分布不均
    int query_id = (int)((random_part + (uint16_t)counter_part) % UINT16_MAX + 1);
    result->query_id = query_id;
    
    int send_len = build_dns_query(domain, send_buffer, sizeof(send_buffer), (uint16_t)query_id, prefer);
    if (send_len <= 0) return cls_dns_detector_error_build_query_failed;
    
    // 构建 DNS 服务器候选列表
    const char *candidates[8] = {0};
    size_t candidate_count = 0;
    
    int candidate_err = build_dns_candidate_list(dns_servers, dns_server_count, prefer, candidates,
                                 &candidate_count, result->dns_source);
    if (candidate_err != cls_dns_detector_error_success) {
        return (cls_dns_detector_error_code)candidate_err;
    }
    
    // 并发查询多个服务器（取最快响应）
    const char *server = NULL;
    size_t recv_len = 0;
    int query_time_ms = 0;
    int send_result = perform_concurrent_dns_queries(send_buffer, (size_t)send_len, candidates,
                                                     candidate_count, timeout_ms, interface_index,
                                                     recv_buffer, &recv_len, &query_time_ms, &server);
    
    if (send_result != cls_dns_detector_error_success) {
        return send_result;
    }
    
    // 保存使用的服务器地址
    if (server) {
        strncpy(result->host_ip, server, sizeof(result->host_ip) - 1);
        result->host_ip[sizeof(result->host_ip) - 1] = '\0';
    }
    result->latency = (double)query_time_ms;
    
    // 解析 DNS 响应
    tiny_dns_header header = {0};
    if (parse_dns_header(recv_buffer, recv_len, &header) != 0) {
        return cls_dns_detector_error_parse_failed;
    }
    
    // 校验 Query ID 是否匹配，防止接受过期或伪造的响应
    if (header.id != (uint16_t)query_id) {
        return cls_dns_detector_error_parse_failed;
    }
    
    // 检测 TC (Truncated) 标志，如果设置了则使用 TCP 重试
    BOOL is_truncated = (header.flags & 0x0200) != 0;
    if (is_truncated && server) {
        // 使用 TCP 重试查询以获取完整响应
        size_t tcp_recv_len = 0;
        int tcp_query_time_ms = 0;
        int tcp_result = send_dns_with_network_tcp(send_buffer, (size_t)send_len, server, timeout_ms,
                                                   interface_index, recv_buffer, &tcp_recv_len, &tcp_query_time_ms);
        if (tcp_result == cls_dns_detector_error_success && tcp_recv_len > 0) {
            recv_len = tcp_recv_len;
            query_time_ms = tcp_query_time_ms;
            result->latency = (double)query_time_ms;
            
            // 重新解析 TCP 响应
            if (parse_dns_header(recv_buffer, recv_len, &header) != 0) {
                return cls_dns_detector_error_parse_failed;
            }
            if (header.id != (uint16_t)query_id) {
                return cls_dns_detector_error_parse_failed;
            }
            // TCP 响应不应该有 TC 标志
            is_truncated = NO;
        } else {
            // TCP 查询失败，如果 UDP 响应被截断，返回错误而不是使用不完整的数据
            if (is_truncated) {
                return cls_dns_detector_error_parse_failed;
            }
        }
    }
    
    // 提取状态和标志
    uint8_t rcode = header.flags & 0x0F;
    const char *status = get_status_string(rcode);
    strncpy(result->status, status, sizeof(result->status) - 1);
    result->status[sizeof(result->status) - 1] = '\0';
    
    build_flags_string(header.flags, result->flags, sizeof(result->flags));
    
    // 保存 DNS 头部统计信息（原始统计，不修改）
    result->query_count = (int)header.qdcount;      // QUERY
    result->authority_count = (int)header.nscount;  // AUTHORITY
    result->additional_count = (int)header.arcount;  // ADDITIONAL
    
    // 解析答案记录（只包括 ANSWER 和 ADDITIONAL，不包括 AUTHORITY）
    DnsAnswerRecordArray answers;
    dns_answer_record_array_init(&answers);
    
    int parse_ret = dns_detector_parse_answers(recv_buffer, recv_len, &header, &answers);
    if (parse_ret != 0) {
        dns_answer_record_array_free(&answers);
        return cls_dns_detector_error_parse_failed;
    }
    
    // 保存答案记录到 result（最多100条）
    int max_answers = ((int)answers.count > 100) ? 100 : (int)answers.count;
    // 保存实际解析的记录数（answers.count），而不是保存的数量
    // 这样JSON输出中的ANSWER字段可以正确反映实际解析的记录数
    result->answer_count = (int)answers.count;  // 保存实际解析的记录数
    // header中的ancount和arcount已经在上面保存，这里不再修改
    
    memset(result->answers, 0, sizeof(result->answers));
    
    for (int i = 0; i < max_answers; i++) {
        const DnsAnswerRecord *src = &answers.records[i];
        cls_dns_answer_record *dst = &result->answers[i];
        
        memset(dst, 0, sizeof(cls_dns_answer_record));
        
        if (src->name && src->name[0] != '\0') {
            size_t name_len = strnlen(src->name, sizeof(dst->name) - 1);
            if (name_len > 0) {
                memcpy(dst->name, src->name, name_len);
                dst->name[name_len] = '\0';
            }
        }
        if (src->type && src->type[0] != '\0') {
            size_t type_len = strnlen(src->type, sizeof(dst->type) - 1);
            if (type_len > 0) {
                memcpy(dst->type, src->type, type_len);
                dst->type[type_len] = '\0';
            }
        }
        if (src->value && src->value[0] != '\0') {
            size_t value_len = strnlen(src->value, sizeof(dst->value) - 1);
            if (value_len > 0) {
                memcpy(dst->value, src->value, value_len);
                dst->value[value_len] = '\0';
            }
        }
        dst->ttl = src->ttl;
    }
    
    dns_answer_record_array_free(&answers);
    
    return cls_dns_detector_error_success;
}

cls_dns_detector_error_code cls_dns_detector_perform_dns(const char *domain,
                                                         const cls_dns_detector_config * _Nullable config,
                                                         cls_dns_detector_result *result) {
    if (!domain || !result) return cls_dns_detector_error_invalid_param;
    
    const char *const *dns_servers = NULL;
    size_t dns_server_count = 0;
    int timeout_ms = DNS_DEFAULT_TIMEOUT_MS;
    int prefer = 0;
    unsigned int interface_index = 0;
    BOOL prefer_auto = NO;
    
    if (config) {
        dns_servers = config->dns_servers;
        
        if (dns_servers != NULL) {
            dns_server_count = calculate_dns_server_count(dns_servers);
        }
        
        if (config->timeout_ms > 0) {
            timeout_ms = config->timeout_ms;
            if (timeout_ms < DNS_MIN_TIMEOUT_MS) timeout_ms = DNS_MIN_TIMEOUT_MS;
            if (timeout_ms > DNS_MAX_TIMEOUT_MS) timeout_ms = DNS_MAX_TIMEOUT_MS;
        }
        if (config->prefer < 0) {
            prefer_auto = YES;
        } else if (config->prefer >= 0 && config->prefer <= 3) {
            prefer = config->prefer;
        } else {
            // prefer > 3 或无效值，使用默认值 0 (IPv4优先)
            prefer = 0;
        }
        if (config->interface_index > 0) {
            interface_index = config->interface_index;
        }
    }
    
    int prefer_options[2] = {prefer, 0};
    size_t prefer_option_count = 1;
    if (prefer_auto) {
        prefer_options[0] = 1; // IPv6 优先
        prefer_options[1] = 0; // 回退到 IPv4
        prefer_option_count = 2;
    }
    
    cls_dns_detector_error_code last_error = cls_dns_detector_error_unknown;
    for (size_t i = 0; i < prefer_option_count; i++) {
        cls_dns_detector_result temp_result;
        cls_dns_detector_error_code code = perform_dns_with_prefer(domain,
                                                                   dns_servers,
                                                                   dns_server_count,
                                                                   prefer_options[i],
                                                                   timeout_ms,
                                                                   interface_index,
                                                                   &temp_result);
        last_error = code;
        if (code == cls_dns_detector_error_success) {
            *result = temp_result;
            return code;
        }
    }
    
    memset(result, 0, sizeof(cls_dns_detector_result));
    strncpy(result->domain, domain, sizeof(result->domain) - 1);
    result->domain[sizeof(result->domain) - 1] = '\0';
    strncpy(result->method, "dns", sizeof(result->method) - 1);
    result->method[sizeof(result->method) - 1] = '\0';
    result->prefer = prefer_options[prefer_option_count - 1];
    return last_error;
}

size_t cls_dns_detector_result_json_size(const cls_dns_detector_result *result) {
    if (!result) {
        // 如果 result 为 NULL，返回最大可能估算值
        // 基础字段(1000) + 最大域名长度转义(256*4=1024) + 最大记录数(100*500=50000)
        return 1000 + 256 * 4 + 100 * 500;
    }
    
    // 计算实际所需缓冲区大小
    // 基础字段：约 1000 字节（包含 JSON 结构、固定字段等）
    size_t base_size = 1000;
    
    // 域名长度（转义后可能翻倍，保守估计为 4 倍）
    size_t domain_len = strlen(result->domain);
    size_t domain_size = domain_len * 4;
    
    // 每个答案记录：约 500 字节（包含 name、type、value 的转义和 JSON 结构）
    // name 最大 256，转义后约 512；type 最大 8，转义后约 16；value 最大 512，转义后约 1024
    // 加上 JSON 结构（逗号、引号、大括号等）约 100 字节
    // 保守估计每条记录约 500 字节
    size_t answer_size = result->answer_count * 500;
    
    // 额外预留空间（用于其他字段如 host_ip、status、flags 等）
    size_t extra_size = 500;
    
    return base_size + domain_size + answer_size + extra_size;
}

int cls_dns_detector_result_to_json(const cls_dns_detector_result *result,
                                    cls_dns_detector_error_code error_code,
                                    char *json_buffer,
                                    size_t buffer_size) {
    if (!result || !json_buffer || buffer_size == 0) return -1;
    
    // 预检查：估算所需缓冲区大小（更保守的估算）
    // 使用辅助函数计算所需大小
    size_t estimated_size = cls_dns_detector_result_json_size(result);
    if (estimated_size > buffer_size) {
        // 缓冲区可能不够，返回错误而不是继续尝试
        // 这样可以避免生成不完整的JSON
        return -1;
    }
    
    // 如果出错，生成错误 JSON（对齐 ping：error_code / error_message 在末尾追加）
    if (error_code != cls_dns_detector_error_success) {
        const char *error_name = "unknown";
        switch (error_code) {
            case cls_dns_detector_error_success: error_name = "success"; break;
            case cls_dns_detector_error_invalid_param: error_name = "invalid_param"; break;
            case cls_dns_detector_error_build_query_failed: error_name = "build_query_failed"; break;
            case cls_dns_detector_error_send_failed: error_name = "send_failed"; break;
            case cls_dns_detector_error_timeout: error_name = "timeout"; break;
            case cls_dns_detector_error_parse_failed: error_name = "parse_failed"; break;
            case cls_dns_detector_error_json_failed: error_name = "json_failed"; break;
            case cls_dns_detector_error_no_valid_server: error_name = "no_valid_server"; break;
            case cls_dns_detector_error_unknown: error_name = "unknown"; break;
            default:
                error_name = "unknown";
                break;
        }
        
        // 按 ping 的风格输出：先业务字段，再追加 error_* 字段
        char escaped_domain_err[2048];
        char escaped_method_err[256];
        char escaped_error_msg[256];
        if (json_escape(result->domain, escaped_domain_err, sizeof(escaped_domain_err)) < 0) return -1;
        if (json_escape(result->method, escaped_method_err, sizeof(escaped_method_err)) < 0) return -1;
        if (json_escape(error_name, escaped_error_msg, sizeof(escaped_error_msg)) < 0) return -1;
        
        int pos = 0;
        int n = snprintf(json_buffer + pos, buffer_size - pos, "{\n");
        if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
        pos += n;
        
        n = snprintf(json_buffer + pos, buffer_size - pos, "  \"method\": \"%s\",\n", escaped_method_err);
        if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
        pos += n;
        
        n = snprintf(json_buffer + pos, buffer_size - pos, "  \"domain\": \"%s\",\n", escaped_domain_err);
        if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
        pos += n;

        if (error_code != cls_dns_detector_error_success || (escaped_error_msg[0] != '\0')){
            // 末尾追加 errCode / errMsg ping 的输出位置）
            n = snprintf(json_buffer + pos, buffer_size - pos, "  \"errCode\": %ld,\n", (long)error_code);
            if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
            pos += n;
            
            n = snprintf(json_buffer + pos, buffer_size - pos, "  \"errMsg\": \"%s\"\n", escaped_error_msg);
            if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
            pos += n;
        }
        
        n = snprintf(json_buffer + pos, buffer_size - pos, "}");
        if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
        pos += n;
        
        return pos;
    }
    
    // 生成成功 JSON（简化版，完整版需要重新查询获取答案记录）
    char escaped[2048];
    if (json_escape(result->domain, escaped, sizeof(escaped)) < 0) return -1; // 检查转义是否成功
    
    int pos = 0;
    int n = snprintf(json_buffer + pos, buffer_size - pos, "{\n");
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"method\": \"%s\",\n", result->method);
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"domain\": \"%s\",\n", escaped);
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"status\": \"%s\",\n", result->status);
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"id\": %d,\n", result->query_id);
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"flags\": \"%s\",\n", result->flags);
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"latency\": %.3f,\n", result->latency);
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    if (result->host_ip[0] != '\0') {
        if (json_escape(result->host_ip, escaped, sizeof(escaped)) < 0) return -1; // 检查转义是否成功
        n = snprintf(json_buffer + pos, buffer_size - pos, "  \"host_ip\": \"%s\",\n", escaped);
    } else {
        n = snprintf(json_buffer + pos, buffer_size - pos, "  \"host_ip\": null,\n");
    }
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    const char *qtype_str = (result->prefer == 1 || result->prefer == 3) ? "AAAA" : "A";
    // 转义domain用于JSON输出（注意：这里result->domain已经在前面转义过，但QUESTION-SECTION需要重新转义）
    char escaped_domain_question[2048];
    if (json_escape(result->domain, escaped_domain_question, sizeof(escaped_domain_question)) < 0) return -1;
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"QUESTION_SECTION\": [\n    {\"name\": \"%s.\", \"type\": \"%s\"}\n  ],\n", escaped_domain_question, qtype_str);
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    // 输出 ANSWER-SECTION
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"ANSWER_SECTION\": [\n");
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    // 使用单独的计数器跟踪实际输出的记录数量（用于正确输出逗号和 ANSWER 字段）
    int output_count = 0;
    for (int i = 0; i < result->answer_count; i++) {
        const cls_dns_answer_record *ans = &result->answers[i];
        
        // 根据 prefer 参数过滤记录
        // 注意：CNAME 记录是 DNS 解析链的一部分，应该始终输出
        if (result->prefer == 2) {
            // IPv4 only: 输出 A 记录和 CNAME 记录（CNAME 是解析链的一部分）
            if (strcmp(ans->type, "A") != 0 && strcmp(ans->type, "CNAME") != 0) continue;
        } else if (result->prefer == 3) {
            // IPv6 only: 输出 AAAA 记录和 CNAME 记录（CNAME 是解析链的一部分）
            if (strcmp(ans->type, "AAAA") != 0 && strcmp(ans->type, "CNAME") != 0) continue;
        }
        
        // 如果不是第一条输出的记录，添加逗号
        if (output_count > 0) {
            n = snprintf(json_buffer + pos, buffer_size - pos, ",\n");
            if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
            pos += n;
        }
        
        const char *name = ans->name[0] ? ans->name : "";
        const char *atype = ans->type[0] ? ans->type : "";
        const char *value = ans->value[0] ? ans->value : "";
        
        if (json_escape(name, escaped, sizeof(escaped)) < 0) return -1; // 检查转义是否成功
        n = snprintf(json_buffer + pos, buffer_size - pos, "    {\"name\": \"%s\", \"ttl\": %u, \"atype\": \"", escaped, ans->ttl);
        if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
        pos += n;
        
        if (json_escape(atype, escaped, sizeof(escaped)) < 0) return -1; // 检查转义是否成功
        n = snprintf(json_buffer + pos, buffer_size - pos, "%s\", \"value\": \"", escaped);
        if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
        pos += n;
        
        if (json_escape(value, escaped, sizeof(escaped)) < 0) return -1; // 检查转义是否成功
        n = snprintf(json_buffer + pos, buffer_size - pos, "%s\"}", escaped);
        if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
        pos += n;
        
        output_count++;  // 增加实际输出的记录计数
    }
    
    n = snprintf(json_buffer + pos, buffer_size - pos, "\n  ],\n");
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    // DNS 统计信息（在 ANSWER-SECTION 之后）
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"QUERY\": %d,\n", result->query_count);
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    // ANSWER 字段应与实际输出列表一致，避免过滤后计数不符
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"ANSWER\": %d,\n", output_count);
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"AUTHORITY\": %d,\n", result->authority_count);
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    n = snprintf(json_buffer + pos, buffer_size - pos, "  \"ADDITIONAL\": %d\n", result->additional_count);
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    n = snprintf(json_buffer + pos, buffer_size - pos, "}");
    if (n < 0 || (size_t)n >= buffer_size - pos) return -1;
    pos += n;
    
    return pos;
}

