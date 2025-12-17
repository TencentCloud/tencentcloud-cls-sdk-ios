//
//  cls_ping_detector.h
//  network_ios
//
//  Created by zhanxiangli on 2025/12/9.
//  Ping 网络探测器 - 使用 Network.framework 实现
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Ping错误码定义
typedef NS_ENUM(NSInteger, cls_ping_detector_error_code) {
    cls_ping_detector_error_success = 0,                    // 成功
    cls_ping_detector_error_invalid_target = -1,            // 无效目标
    cls_ping_detector_error_network_unreachable = -2,       // 网络不可达
    cls_ping_detector_error_timeout = -3,                   // 超时
    cls_ping_detector_error_permission_denied = -4,         // 权限拒绝
    cls_ping_detector_error_socket_create_error = -5,        // 套接字创建失败
    cls_ping_detector_error_resolve_error = -6,             // 域名解析失败
    cls_ping_detector_error_net_binding_failed = -7,         // 网卡绑定失败
    cls_ping_detector_error_cancelled = -8,                // 检测被取消
    cls_ping_detector_error_unknown_error = -99             // 未知错误
};

// Ping网络探测基础信息
typedef struct {
    char target[256];          // 目标地址
    char method[32];          // 探测协议
    char resolved_ip[128];     // 解析后的IP地址
    char interface[64];       // 探测使用的网络接口
    int packets_sent;        // 发送包数
    int packets_received;    // 接收包数
    int ping_size;           // PING 包字节数（包含ICMP头）
    int ttl;                // TTL值
    double total_time;     // 所有包的 RTT 总和 (ms)，不包含包之间的间隔时间
    double packet_loss;    // 丢包率
    double min_rtt;        // 最小RTT(ms)
    double max_rtt;        // 最大RTT(ms)
    double avg_rtt;        // 平均RTT(ms)
    double jitter;         // 抖动(ms)
    double stddev;         // RTT标准差
    int bindFailed;          // 绑定失败次数
    int exceptionNum;        // 异常数（发送失败、接收超时等异常次数）
    char error_message[512]; // 错误信息（如果有错误）
} cls_ping_detector_result;

// Ping 配置参数
typedef struct {
    int packet_size;      // 包大小（字节），不包含ICMP头，<=0表示使用默认值56
    int ttl;              // TTL值（1-255），<=0表示使用默认值64
    int timeout_ms;       // 超时时间（毫秒），<=0表示使用默认值2000
    int interval_ms;      // 发送间隔（毫秒），<=0表示使用默认值200
    int times;            // 探测次数，<=0表示使用默认值10
    unsigned int interface_index;  // 网卡索引，0表示使用默认网卡
    int prefer;     // IP版本偏好：0=IPv4优先, 1=IPv6优先, 2=IPv4 only, 3=IPv6 only，<0表示自动检测
} cls_ping_detector_config;

/**
 * 执行 ICMP Ping 探测
 * @param target 目标地址（域名或IP）
 * @param config 配置参数（可以为NULL，使用默认值）
 * @param result 输出结果（不能为NULL）
 * @return 错误码，成功返回 cls_ping_detector_error_success
 */
cls_ping_detector_error_code cls_ping_detector_perform_ping(const char *target, 
                                                             const cls_ping_detector_config * _Nullable config,
                                                             cls_ping_detector_result *result);

/**
 * 将 Ping 结果转换为 JSON 格式
 * @param result Ping 探测结果
 * @param error_code 错误码
 * @param json_buffer 输出缓冲区
 * @param buffer_size 缓冲区大小
 * @return 成功返回写入的字节数，失败返回-1
 */
int cls_ping_detector_result_to_json(const cls_ping_detector_result *result, 
                                     cls_ping_detector_error_code error_code,
                                     char *json_buffer, 
                                     size_t buffer_size);

NS_ASSUME_NONNULL_END
