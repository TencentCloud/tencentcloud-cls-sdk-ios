//
//  cls_mtr_detector.h
//  network_ios
//
//  MTR 网络路径探测器 - 使用 BSD socket
//  支持 ICMP、UDP 和 TCP 三种协议
//

#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/// MTR 错误码
typedef NS_ENUM(NSInteger, cls_mtr_detector_error_code) {
    cls_mtr_detector_error_success = 0,                    // 成功
    cls_mtr_detector_error_invalid_target = -1,            // 无效目标
    cls_mtr_detector_error_network_unreachable = -2,       // 网络不可达
    cls_mtr_detector_error_timeout = -3,                   // 超时
    cls_mtr_detector_error_permission_denied = -4,         // 权限拒绝
    cls_mtr_detector_error_socket_create_error = -5,       // 套接字创建失败
    cls_mtr_detector_error_resolve_error = -6,             // 域名解析失败
    cls_mtr_detector_error_net_binding_failed = -7,        // 网卡绑定失败
    cls_mtr_detector_error_invalid_param = -8,             // 无效参数（如不支持的协议）

    // 更可解释的系统调用错误（便于上层区分权限/网络策略/资源耗尽/参数问题等）
    cls_mtr_detector_error_setsockopt_failed = -9,         // setsockopt 失败（如 TTL/hops 设置失败）
    cls_mtr_detector_error_send_failed = -10,              // send/sendto 失败
    cls_mtr_detector_error_recv_failed = -11,              // recv/recvfrom/recvmsg/select 失败
    cls_mtr_detector_error_connect_failed = -12,           // connect 失败（非预期/致命场景）
    cls_mtr_detector_error_host_unreachable = -13,         // 主机不可达（更细分：EHOSTUNREACH 等）
    cls_mtr_detector_error_resource_exhausted = -14,       // 资源耗尽（如 ENOBUFS/ENOMEM/EMFILE 等）
    cls_mtr_detector_error_address_not_available = -15,    // 地址不可用（如 EADDRNOTAVAIL）
    cls_mtr_detector_error_address_in_use = -16,           // 地址/端口已被占用（如 EADDRINUSE）
    cls_mtr_detector_error_unknown_error = -99              // 未知错误
};

/// MTR 跳结果结构
typedef struct {
    int hop;                    // 跳数
    char ip[128];               // 响应IP地址
    double loss;                // 丢包率(0~1)，0=无丢包，1=100%丢包
    double latency;             // 平均延迟(ms)
    double latency_min;         // 最小延迟(ms)
    double latency_max;         // 最大延迟(ms)
    double stddev;              // 延迟标准差
    int responseNum;           // 收到响应次数
} cls_mtr_hop_result;

/// MTR 路径结果结构
typedef struct {
    char method[32];            // 探测方法 "mtr"
    char host[256];             // 目标主机
    char host_ip[128];          // 目标主机 IP
    char type[32];              // 路径类型
    char path[512];             // 路径字符串
    int lastHop;                // 最后跳数
    long long timestamp;        // 时间戳
    char interface_name[256];   // 网络接口
    char protocol[16];          // 协议 "icmp"、"udp"、"tcp"
    int exceptionNum;           // 异常数量
    int bindFailed;             // 绑定失败次数
    cls_mtr_hop_result *results; // 跳结果数组（动态分配）
    size_t results_count;       // 跳结果数量
    size_t results_capacity;    // 跳结果容量
    int last_errno;             // 最近一次“致命错误”的 errno（0 表示无）
    char last_error_op[32];     // 最近一次“致命错误”的操作（如 "sendto"/"setsockopt"/"connect"）

} cls_mtr_path_result;

/// MTR 探测结果结构
typedef struct {
    char target[256];           // 目标地址
    char method[32];            // 检测方法 "mtr"
    int max_paths;              // 最大路径数
    char src[32];               // 来源标识
    cls_mtr_detector_error_code error_code;    // 错误码
    char error_message[256];    // 错误信息
    cls_mtr_path_result *paths; // 路径结果数组
    size_t paths_count;         // 路径数量
    size_t paths_capacity;      // 路径容量
} cls_mtr_detector_result;

/// MTR 配置参数
typedef struct {
    const char *protocol;       // 协议类型 "icmp"、"udp"、"tcp"
    int max_ttl;                // 最大TTL值（1-255），<=0 表示使用默认值 30
    int timeout_ms;             // 超时时间（毫秒），<=0 表示使用默认值 2000
    int times;                  // 每跳探测次数，<=0 表示使用默认值 10
    unsigned int interface_index; // 网卡索引，0 表示使用默认网卡
    int prefer;                 // IP版本偏好：0=IPv4优先, 1=IPv6优先, 2=IPv4 only, 3=IPv6 only
    int tcp_dst_port;           // TCP 探测目的端口（1-65535），<=0 表示使用默认值 80
} cls_mtr_detector_config;

/**
 * 执行 MTR 探测
 * @param target 目标地址（域名或IP）
 * @param config 配置参数（可以为 NULL，使用默认值）
 * @param result 输出结果（不能为 NULL）
 * @return 错误码，成功返回 cls_mtr_detector_error_success
 */
cls_mtr_detector_error_code cls_mtr_detector_perform_mtr(const char *target,
                                                         const cls_mtr_detector_config * _Nullable config,
                                                         cls_mtr_detector_result *result);

/**
 * 将 MTR 结果转换为 JSON 格式
 * @param result MTR 探测结果（包含 error_code 字段）
 * @param json_buffer 输出缓冲区
 * @param buffer_size 缓冲区大小
 * @return 成功返回写入的字节数（不包括结尾的 '\0'），失败返回-1
 * @note 当缓冲区不足时，函数会在写入过程中检测到空间不足并返回-1，不会发生缓冲区溢出。
 *       调用者应确保提供足够大的缓冲区（建议至少 4KB 或更大，具体取决于 paths 数量和 hop 数量）。
 *       如果返回-1，可能是以下原因：
 *       - 参数无效（result 或 json_buffer 为 NULL，或 buffer_size 为 0）
 *       - 缓冲区空间不足（在写入过程中检测到空间不足，已写入的数据可能不完整）
 */
int cls_mtr_detector_result_to_json(const cls_mtr_detector_result *result,
                                    char *json_buffer,
                                    size_t buffer_size);

/**
 * 释放 MTR 探测结果内存
 * @param result MTR 探测结果（不能为 NULL）
 */
void cls_mtr_detector_free_result(cls_mtr_detector_result *result);

NS_ASSUME_NONNULL_END
