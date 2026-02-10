//
//  cls_dns_detector.h
//  network_ios
//
//  使用 Network.framework 的 DNS 探测器
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// DNS 探测错误码
typedef NS_ENUM(NSInteger, cls_dns_detector_error_code) {
    cls_dns_detector_error_success = 0,              // 成功
    cls_dns_detector_error_invalid_param = -1,       // 入参错误
    cls_dns_detector_error_build_query_failed = -2,  // 构建查询失败
    cls_dns_detector_error_send_failed = -3,         // 发送失败
    cls_dns_detector_error_timeout = -4,             // 超时
    cls_dns_detector_error_parse_failed = -5,        // 解析失败
    cls_dns_detector_error_json_failed = -6,         // JSON 生成失败
    cls_dns_detector_error_no_valid_server = -7,     // 无可用 DNS 服务器（如 IPv6 only 但无 IPv6）
    cls_dns_detector_error_unknown = -99             // 未知错误
};

/// DNS 答案记录
typedef struct {
    char name[256];          // 域名
    char type[8];            // 记录类型（A、AAAA、CNAME、TXT 等）
    uint32_t ttl;             // 生存时间
    char value[512];         // 记录值
} cls_dns_answer_record;

/// DNS 网络探测基础信息
typedef struct {
    char domain[256];         // 查询的域名
    char method[4];          // 探测协议（"dns"）
    char host_ip[64];        // 使用的 DNS 服务器地址
    char dns_source[16];      // DNS 来源（"specified"=用户指定，"public"=公共备用）
    int query_id;             // DNS 查询 ID
    char status[16];          // DNS 状态（"NOERROR", "NXDOMAIN" 等）
    char flags[32];          // DNS 标志位（"qr rd ra" 等）
    double latency;           // 查询耗时（毫秒）
    int query_count;          // 查询数量 (QUERY / qdcount)
    int answer_count;         // 回答数量 (ANSWER / ancount)
    int authority_count;      // 权威记录数量 (AUTHORITY / nscount)
    int additional_count;     // 附加记录数量 (ADDITIONAL / arcount)
    cls_dns_answer_record answers[30];  // 答案记录数组（最多30条）
    int prefer;               // IP 版本偏好：0=IPv4优先, 1=IPv6优先, 2=IPv4 only, 3=IPv6 only
} cls_dns_detector_result;

/// DNS 配置参数
typedef struct {
    const char * _Nonnull const * _Nullable dns_servers;  // DNS 服务器列表（可以为 NULL，使用默认公共 DNS），数组必须以 NULL 结尾，长度会自动计算
    int timeout_ms;                   // 超时时间（毫秒），<=0 表示使用默认值 5000
    unsigned int interface_index;     // 网卡索引，0 表示使用默认网卡
    int prefer;                       // IP 版本偏好：0=IPv4优先, 1=IPv6优先, 2=IPv4 only, 3=IPv6 only，<0 表示自动检测
} cls_dns_detector_config;

/**
 * 执行 DNS 探测
 * @param domain 查询的域名
 * @param config 配置参数（可以为 NULL，使用默认值）
 * @param result 输出结果（不能为 NULL）
 * @return 错误码，成功返回 cls_dns_detector_error_success
 */
cls_dns_detector_error_code cls_dns_detector_perform_dns(const char *domain,
                                                         const cls_dns_detector_config * _Nullable config,
                                                         cls_dns_detector_result *result);

/**
 * 计算将 DNS 结果转换为 JSON 格式所需的最小缓冲区大小
 * @param result DNS 探测结果（可以为 NULL，使用最大估算值）
 * @return 所需缓冲区大小（字节数），失败返回 0
 * 
 * 缓冲区大小计算公式：
 * - 基础字段：约 1000 字节
 * - 域名（转义后可能翻倍）：domain_len * 4
 * - 每个答案记录：约 500 字节
 * - 最大可能大小：约 52000 字节（100 条记录 + 最大域名长度）
 * 
 * 建议：为安全起见，建议分配至少 65536 字节（64KB）的缓冲区
 */
size_t cls_dns_detector_result_json_size(const cls_dns_detector_result * _Nullable result);

/**
 * 将 DNS 结果转换为 JSON 格式
 * @param result DNS 探测结果
 * @param error_code 错误码
 * @param json_buffer 输出缓冲区
 * @param buffer_size 缓冲区大小（建议使用 cls_dns_detector_result_json_size 计算所需大小）
 * @return 成功返回写入的字节数，失败返回-1
 * 
 * 缓冲区大小说明：
 * - 最小建议大小：65536 字节（64KB）
 * - 最大可能大小：约 52000 字节（100 条记录 + 最大域名长度）
 * - 可使用 cls_dns_detector_result_json_size 函数计算精确大小
 */
int cls_dns_detector_result_to_json(const cls_dns_detector_result *result,
                                    cls_dns_detector_error_code error_code,
                                    char *json_buffer,
                                    size_t buffer_size);

NS_ASSUME_NONNULL_END

