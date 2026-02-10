#import "CLSHttpingV2.h"
#import "CLSRequestValidator.h"
#import "CLSNetworkUtils.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CLSResponse.h"
#import "CLSIdGenerator.h"
#import "CLSSPanBuilder.h"
#import "CLSCocoa.h"
#import "CLSStringUtils.h"
#import "ClsNetworkDiagnosis.h"  // 引入以获取全局 userEx
#import <Network/Network.h>
#import <netdb.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#if __has_include(<Security/SecProtocolOptions.h>)
#import <Security/SecProtocolOptions.h>
#endif

/// 释放 Network.framework 的 C 对象（path/endpoint 等），通过 dlsym 调用避免 ARC 将 nw_release 解析为 objc release
static void cls_nw_object_release(void *obj) {
    if (!obj) return;
    static void (*release_fn)(void *) = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        release_fn = (void (*)(void *))dlsym(RTLD_DEFAULT, "nw_release");
    });
    if (release_fn) release_fn(obj);
}

/// 根据 nw_connection_state_failed 的 nw_error 及是否为 HTTPS，生成可读的 NSError（便于上报和日志分析）
static NSError *cls_connection_failed_error(nw_error_t nw_err, BOOL isHTTPS) {
    NSString *msg = nil;
    if (nw_err) {
        static int (*get_code)(nw_error_t) = NULL;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            get_code = (int (*)(nw_error_t))dlsym(RTLD_DEFAULT, "nw_error_get_error_code");
        });
        if (get_code) {
            int code = get_code(nw_err);
            // POSIX 无专门“证书校验失败”，TLS 失败在部分系统上会映射到 errSec 或特定 code；这里仅做提示
            if (isHTTPS && (code != 0))
                msg = [NSString stringWithFormat:@"Connection failed (TLS/certificate verify failed, code=%d)", code];
        }
    }
    if (!msg) msg = isHTTPS ? @"Connection failed (TLS/certificate verify failed?)" : @"Connection failed";
    return [NSError errorWithDomain:@"CLSHttpingErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: msg}];
}

@interface CLSMultiInterfaceHttping ()
/// Network.framework 路径下解析到的 HTTP 状态码，用于 buildFinalReportDictWithTask 在 task 为 nil 时使用
@property (nonatomic, assign) NSInteger networkResultStatusCode;
/// Network.framework 路径下首次收到响应数据的时间（用于填充 firstByteTime/desc）
@property (nonatomic, assign) CFAbsoluteTime firstByteArrivalTime;
/// Network.framework 路径下连接就绪时间（TCP+TLS 完成），用于填充 connectEnd/secureConnectEnd、tcpTime/sslTime
@property (nonatomic, assign) CFAbsoluteTime connectionReadyTime;
/// Network.framework 路径下 TCP 连接完成时间（TLS 握手前），用于精确计算 tcpTime
@property (nonatomic, assign) CFAbsoluteTime tcpReadyTime;
/// Network.framework 路径下 DNS 解析开始/结束时间（getaddrinfo 测得，用于真实 dnsStart/dnsEnd/dnsTime）
@property (nonatomic, assign) CFAbsoluteTime dnsStartTime;
@property (nonatomic, assign) CFAbsoluteTime dnsEndTime;
/// Network.framework 路径下解析到的远端 IP（用于 remoteAddr / host_ip）
@property (nonatomic, copy) NSString *resolvedRemoteAddress;
/// Network.framework 路径下已发送字节数（用于 buildFinalReportDict 的 sendBytes）
@property (nonatomic, assign) NSUInteger sentBytes;
@end

@implementation CLSMultiInterfaceHttping

- (instancetype)initWithRequest:(CLSHttpRequest *)request {
    self = [super init];
    if (self) {
        _request = request;
        _timingMetrics = [NSMutableDictionary dictionary];
        _responseData = [NSMutableData data];
        _interfaceInfo = @{};
        _networkResultStatusCode = -2;
        _firstByteArrivalTime = 0;
        _connectionReadyTime = 0;
        _tcpReadyTime = 0;
        _dnsStartTime = 0;
        _dnsEndTime = 0;
        _sentBytes = 0;
    }
    return self;
}

- (void)dealloc {
    // Network.framework 和 NSURLSession 路径都使用 dispatch_after 超时，无需 timer 清理
}

- (NSURLSessionConfiguration *)createSessionConfigurationForInterface {
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    // 配置网络超时参数（timeout 从毫秒转换为秒，NSURLSession 使用秒单位）
    NSTimeInterval timeoutInSeconds = self.request.timeout / 1000.0;
    sessionConfig.timeoutIntervalForRequest = timeoutInSeconds;
    sessionConfig.timeoutIntervalForResource = timeoutInSeconds;
    NSString *currentInterfaceName = self.interfaceInfo[@"name"];
    
    if ([currentInterfaceName hasPrefix:@"en"]) {
        // Wi-Fi 接口（en0, en1...）
        sessionConfig.networkServiceType = NSURLNetworkServiceTypeVideo;
        sessionConfig.allowsCellularAccess = NO;  // 禁用蜂窝网络
        NSLog(@"[HTTP] 配置 Wi-Fi 接口: %@", currentInterfaceName);
    } else if ([currentInterfaceName hasPrefix:@"pdp_ip"]) {
        // 蜂窝网络接口（pdp_ip0, pdp_ip1...）
        sessionConfig.networkServiceType = NSURLNetworkServiceTypeVoIP;
        sessionConfig.allowsCellularAccess = YES;  // 允许蜂窝网络
        NSLog(@"[HTTP] 配置蜂窝接口: %@", currentInterfaceName);
    } else {
        // 其他接口（回环、VPN、桥接等）- 兜底配置
        sessionConfig.networkServiceType = NSURLNetworkServiceTypeDefault;
        sessionConfig.allowsCellularAccess = YES;  // ✅ 修复：允许所有网络类型
        NSLog(@"[HTTP] 配置其他接口: %@ (使用默认配置)", currentInterfaceName);
    }

    if (@available(iOS 11.0, *)) {
        if (self.request.enableMultiplePortsDetect && sessionConfig.networkServiceType == NSURLNetworkServiceTypeDefault) {
            sessionConfig.multipathServiceType = NSURLSessionMultipathServiceTypeHandover;
        } else {
            sessionConfig.multipathServiceType = NSURLSessionMultipathServiceTypeNone;
        }
    }

    return sessionConfig;
}

#pragma mark - HTTP Ping 执行
- (void)startHttpingWithCompletion:(NSDictionary *)currentInterface
                        completion:(void (^)(NSDictionary *finalReportDict, NSError *error))completion {
    self.completionHandler = completion;
    self.interfaceInfo = [currentInterface copy];
    self.processStartTime = CFAbsoluteTimeGetCurrent();
    self.networkResultStatusCode = -2;

    NSURL *url = [NSURL URLWithString:self.request.domain];
    if (!url) {
        NSError *error = [NSError errorWithDomain:@"CLSHttpingErrorDomain"
                                              code:-2
                                          userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}];
        [self completeWithError:error];
        return;
    }

    NSString *interfaceName = self.interfaceInfo[@"name"] ?: @"";
#if __has_include(<Network/Network.h>) && TARGET_OS_IPHONE
    // 参考 Ping/MTR：使用 Network.framework 强制按接口类型探测（requiredInterfaceType），避免系统始终走 WiFi
    // ⚠️ 模拟器环境禁用 Network.framework：旧版模拟器（Xcode 15.2 / iOS 17.2）的 nw_parameters_set_required_interface_type 存在 bug，导致连接超时
#if TARGET_OS_SIMULATOR
    BOOL useNetworkFramework = NO;  // 模拟器环境强制使用 NSURLSession 路径
#else
    BOOL useNetworkFramework = (interfaceName.length > 0 &&
        ([interfaceName hasPrefix:@"en"] || [interfaceName hasPrefix:@"pdp_ip"]));
#endif
    if (useNetworkFramework && @available(iOS 12.0, *)) {
        [self startHttpingWithNetworkFrameworkCompletion:completion];
        return;
    }
#endif

    // 回退：NSURLSession（无法强制接口时使用）
    NSURLSessionConfiguration *sessionConfig = [self createSessionConfigurationForInterface];
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 1;
    queue.name = [NSString stringWithFormat:@"CLSHttpingQueue.%@", self.interfaceInfo[@"name"]];
    self.urlSession = [NSURLSession sessionWithConfiguration:sessionConfig
                                                   delegate:self
                                              delegateQueue:queue];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    // timeout 从毫秒转换为秒（NSURLRequest 使用秒单位）
    request.timeoutInterval = self.request.timeout / 1000.0;
    [request setValue:@"CLSHttping/2.0.0" forHTTPHeaderField:@"User-Agent"];
    [request setValue:self.interfaceInfo[@"name"] forHTTPHeaderField:@"X-Network-Interface"];

    self.taskStartTime = CFAbsoluteTimeGetCurrent();
    NSURLSessionDataTask *task = [self.urlSession dataTaskWithRequest:request];
    [task resume];
}

#if __has_include(<Network/Network.h>) && TARGET_OS_IPHONE
#pragma mark - Network.framework 多网卡强制探测（requiredInterfaceType）
- (void)startHttpingWithNetworkFrameworkCompletion:(void (^)(NSDictionary *finalReportDict, NSError *error))completion
API_AVAILABLE(ios(12.0)) {
    NSURL *url = [NSURL URLWithString:self.request.domain];
    if (!url || !url.host) {
        NSError *err = [NSError errorWithDomain:@"CLSHttpingErrorDomain" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSDictionary *dict = [self buildFinalReportDictWithTask:nil error:err];
            if (completion) completion(dict, err);
        });
        return;
    }

    NSString *host = url.host;
    NSString *path = url.path.length > 0 ? url.path : @"/";
    // 拼出与 NSURLSession 一致的 request-URI（path + query + fragment），避免带参 URL 行为不一致
    NSMutableString *requestURI = [path mutableCopy];
    if (url.query.length) [requestURI appendFormat:@"?%@", url.query];
    if (url.fragment.length) [requestURI appendFormat:@"#%@", url.fragment];
    uint16_t port = (uint16_t)(url.port ? url.port.unsignedShortValue : 443);
    NSString *scheme = (url.scheme ?: @"https").lowercaseString;
    BOOL isHTTPS = [scheme isEqualToString:@"https"];
    if (url.port == nil) {
        port = isHTTPS ? 443 : 80;
    }

    // HTTPS 且关闭证书校验时，使用 C API 创建带自定义 verify 块的 TLS 参数，与 NSURLSession 路径行为一致
#if __has_include(<Security/SecProtocolOptions.h>)
    if (isHTTPS && !self.request.enableSSLVerification) {
        [self startHttpingWithNetworkFrameworkNoSSLWithHost:host path:[requestURI copy] port:port completion:completion];
        return;
    }
#endif

    const char *hostC = host.UTF8String;
    const char *portC = [[@(port) stringValue] UTF8String];
    if (!hostC || !portC) {
        NSError *err = [NSError errorWithDomain:@"CLSHttpingErrorDomain" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid host or port"}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([self buildFinalReportDictWithTask:nil error:err], err);
        });
        return;
    }

    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    __block NSString *hostCopy = [host copy];
    __block NSMutableString *requestURICopy = [requestURI mutableCopy];

    dispatch_async(queue, ^{
        // 1. 先做 DNS 解析并记录真实 dnsStart/dnsEnd（getaddrinfo），带 5 秒超时
        const int64_t dnsTimeoutNs = (int64_t)(5 * NSEC_PER_SEC);
        dispatch_semaphore_t dnsSem = dispatch_semaphore_create(0);
        __block struct addrinfo *res = NULL;
        __block int gaiRet = EAI_AGAIN;

        self.dnsStartTime = CFAbsoluteTimeGetCurrent();
        dispatch_async(queue, ^{
            struct addrinfo hints = {0};
            hints.ai_family = AF_UNSPEC;
            hints.ai_socktype = SOCK_STREAM;
            gaiRet = getaddrinfo(hostC, portC, &hints, &res);
            dispatch_semaphore_signal(dnsSem);
        });
        if (dispatch_semaphore_wait(dnsSem, dispatch_time(DISPATCH_TIME_NOW, dnsTimeoutNs)) != 0) {
            gaiRet = EAI_AGAIN;
        }
        self.dnsEndTime = CFAbsoluteTimeGetCurrent();
        if (gaiRet != 0 || !res) {
            if (res) freeaddrinfo(res);
            res = NULL;
            self.dnsStartTime = 0;
            self.dnsEndTime = 0;
        }

        nw_endpoint_t endpoint = NULL;
        if (res && res->ai_addr) {
            struct sockaddr_storage storage = {0};
            size_t addrlen = (res->ai_addr->sa_family == AF_INET6) ? sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_in);
            memcpy(&storage, res->ai_addr, (res->ai_addrlen < addrlen ? res->ai_addrlen : addrlen));
            if (res->ai_addr->sa_family == AF_INET) {
                ((struct sockaddr_in *)&storage)->sin_port = htons(port);
            } else if (res->ai_addr->sa_family == AF_INET6) {
                ((struct sockaddr_in6 *)&storage)->sin6_port = htons(port);
            }
            // HTTPS 且启用系统 TLS 校验时必须用 host endpoint，否则 TLS 层无 hostname 校验证书会失败或挂起直至超时（enableSSLVerification=YES 超时的原因）
            endpoint = isHTTPS ? nw_endpoint_create_host(hostC, portC) : nw_endpoint_create_address((struct sockaddr *)&storage);
            char ipStr[INET6_ADDRSTRLEN];
            const void *ipPtr = (res->ai_addr->sa_family == AF_INET)
                ? (const void *)&((struct sockaddr_in *)res->ai_addr)->sin_addr
                : (const void *)&((struct sockaddr_in6 *)res->ai_addr)->sin6_addr;
            if (inet_ntop(res->ai_addr->sa_family, ipPtr, ipStr, sizeof(ipStr))) {
                self.resolvedRemoteAddress = [NSString stringWithUTF8String:ipStr];
            }
            freeaddrinfo(res);
        }
        if (!endpoint) {
            endpoint = nw_endpoint_create_host(hostC, portC);
        }

        // 使用显式 block 创建 parameters，避免在部分系统/模拟器上传 NULL 导致 nw_parameters_create_secure_tcp 返回 NULL（HTTP 探测 HTTPS 时报 "Failed to create parameters"）
        nw_parameters_t params = NULL;
        if (isHTTPS) {
            nw_parameters_configure_protocol_block_t use_default_tls = ^(nw_protocol_options_t tls_options) {
                (void)tls_options;  // 使用系统默认 TLS，不修改 options
            };
            params = nw_parameters_create_secure_tcp(use_default_tls, NW_PARAMETERS_DEFAULT_CONFIGURATION);
        } else {
            params = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
        }
        if (!params) {
            NSError *err = [NSError errorWithDomain:@"CLSHttpingErrorDomain" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create parameters"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion([self buildFinalReportDictWithTask:nil error:err], err);
            });
            return;
        }

        NSString *ifName = self.interfaceInfo[@"name"] ?: @"";
        if ([ifName hasPrefix:@"en"]) {
            nw_parameters_set_required_interface_type(params, nw_interface_type_wifi);
            nw_parameters_prohibit_interface_type(params, nw_interface_type_cellular);
        } else if ([ifName hasPrefix:@"pdp_ip"]) {
            nw_parameters_set_required_interface_type(params, nw_interface_type_cellular);
            nw_parameters_prohibit_interface_type(params, nw_interface_type_wifi);
        }

        if (!endpoint) {
            params = NULL;
            NSError *err = [NSError errorWithDomain:@"CLSHttpingErrorDomain" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid endpoint"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion([self buildFinalReportDictWithTask:nil error:err], err);
            });
            return;
        }

        __block nw_connection_t c_conn = nw_connection_create(endpoint, params);
        params = NULL;
        endpoint = NULL;
    if (!c_conn) {
        NSError *err = [NSError errorWithDomain:@"CLSHttpingErrorDomain" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create connection"}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([self buildFinalReportDictWithTask:nil error:err], err);
        });
        return;
    }

    __block BOOL completed = NO;
    __block NSUInteger receivedBytes = 0;
    __block NSInteger statusCode = -2;
    __block CFAbsoluteTime taskStart = CFAbsoluteTimeGetCurrent();
    __weak __typeof(self) weakSelf = self;

    // connectionAlreadyDead=YES 时不再调用 nw_connection_cancel，避免在 state_failed/state_cancelled 时对已由系统回收的连接再 cancel 导致异常退出（Enqueued from com.apple.root.default-qos）
    void (^finish)(NSError *, BOOL) = ^(NSError *error, BOOL connectionAlreadyDead) {
        if (completed) return;
        completed = YES;
        nw_connection_t connToCancel = NULL;
        if (c_conn) {
            if (!connectionAlreadyDead) {
                connToCancel = c_conn;
                c_conn = NULL;
                // 避免在 connection 回调栈内同步 cancel 导致崩溃（Enqueued from com.apple.network.connections）
                dispatch_async(queue, ^{
                    if (connToCancel) nw_connection_cancel(connToCancel);
                });
            } else {
                c_conn = NULL;
            }
        }
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.taskStartTime = taskStart;
        strongSelf.receivedBytes = receivedBytes;
        strongSelf.networkResultStatusCode = statusCode;
        NSDictionary *dict = [strongSelf buildFinalReportDictWithTask:nil error:error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(dict, error);
        });
    };

        nw_connection_set_queue(c_conn, queue);
        nw_connection_set_state_changed_handler(c_conn, ^(nw_connection_state_t state, nw_error_t error) {
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            switch (state) {
            case nw_connection_state_preparing:
                // 🎯 关键：preparing 状态表示 TCP 连接已建立，正在进行 TLS 握手（HTTPS）或等待应用数据（HTTP）
                // 对于 HTTPS：此时 TCP 三次握手完成，即将开始 TLS 握手
                // 对于 HTTP：此时 TCP 连接完成，立即转到 ready
                if (strongSelf.tcpReadyTime == 0) {
                    strongSelf.tcpReadyTime = CFAbsoluteTimeGetCurrent();
                }
                break;
            case nw_connection_state_ready: {
                if (strongSelf.connectionReadyTime == 0) {
                    strongSelf.connectionReadyTime = CFAbsoluteTimeGetCurrent();
                }
                // 如果 tcpReadyTime 未记录（HTTP 快速切换），使用 connectionReadyTime
                if (strongSelf.tcpReadyTime == 0) {
                    strongSelf.tcpReadyTime = strongSelf.connectionReadyTime;
                }
                if (!strongSelf.resolvedRemoteAddress && @available(iOS 14.0, *)) {
                    nw_path_t path = nw_connection_copy_current_path(c_conn);
                    if (path) {
                        nw_endpoint_t remote_ep = nw_path_copy_effective_remote_endpoint(path);
                        if (remote_ep) {
                            const struct sockaddr *addr = nw_endpoint_get_address(remote_ep);
                            if (addr) {
                                char ipStr[INET6_ADDRSTRLEN];
                                const void *ipPtr = (addr->sa_family == AF_INET)
                                    ? (const void *)&((const struct sockaddr_in *)addr)->sin_addr
                                    : (const void *)&((const struct sockaddr_in6 *)addr)->sin6_addr;
                                if (inet_ntop(addr->sa_family, ipPtr, ipStr, sizeof(ipStr))) {
                                    strongSelf.resolvedRemoteAddress = [NSString stringWithUTF8String:ipStr];
                                }
                            }
                            cls_nw_object_release((__bridge void *)remote_ep);
                        }
                        cls_nw_object_release((__bridge void *)path);
                    }
                }
                NSString *req = [NSString stringWithFormat:@"GET %@ HTTP/1.1\r\nHost: %@\r\nUser-Agent: CLSHttping/2.0.0\r\nConnection: close\r\n\r\n", requestURICopy, hostCopy];
                NSData *reqData = [req dataUsingEncoding:NSUTF8StringEncoding];
                strongSelf.sentBytes = reqData.length;
                dispatch_data_t sendData = dispatch_data_create(reqData.bytes, reqData.length, queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                nw_connection_send(c_conn, sendData, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t sendError) {
                    if (sendError) {
                        finish([NSError errorWithDomain:@"CLSHttpingErrorDomain" code:2000 + (int)sendError userInfo:@{NSLocalizedDescriptionKey: @"Send failed"}], NO);
                        return;
                    }
                    nw_connection_receive(c_conn, 1, 65536, ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t recvError) {
                        if (recvError) {
                            finish([NSError errorWithDomain:@"CLSHttpingErrorDomain" code:2000 + (int)recvError userInfo:@{NSLocalizedDescriptionKey: @"Receive failed"}], NO);
                            return;
                        }
                        if (content && dispatch_data_get_size(content) > 0) {
                            __strong __typeof(weakSelf) strongSelfRecv = weakSelf;
                            if (strongSelfRecv && strongSelfRecv.firstByteArrivalTime == 0) {
                                strongSelfRecv.firstByteArrivalTime = CFAbsoluteTimeGetCurrent();
                            }
                            size_t size = 0;
                            const void *buf = NULL;
                            dispatch_data_t mapped = dispatch_data_create_map(content, &buf, &size);
                            if (buf && size > 0) {
                                receivedBytes += size;
                                if (statusCode == -2) {
                                    NSData *chunk = [NSData dataWithBytes:buf length:size];
                                    NSString *firstLine = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
                                    NSArray *lines = [firstLine componentsSeparatedByString:@"\r\n"];
                                    if (lines.count) {
                                        NSArray *parts = [lines[0] componentsSeparatedByString:@" "];
                                        if (parts.count >= 2) statusCode = [parts[1] integerValue];
                                    }
                                }
                            }
                            (void)mapped;
                        }
                        // 成功收到数据后不再 cancel，避免与 connection 自关闭竞争导致崩溃
                        finish(nil, YES);
                    });
                });
                break;
            }
            case nw_connection_state_failed:
                finish(cls_connection_failed_error(error, isHTTPS), YES);  // 连接已由系统置为 failed，不再 cancel
                break;
            case nw_connection_state_cancelled:
                if (!completed) finish([NSError errorWithDomain:@"CLSHttpingErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Connection cancelled"}], YES);
                break;
            default:
                break;
        }
    });
    nw_connection_start(c_conn);

    // timeout 从毫秒转换为纳秒
    int64_t timeoutInNanoseconds = (int64_t)(self.request.timeout * NSEC_PER_MSEC);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, timeoutInNanoseconds), queue, ^{
        if (!completed) finish([NSError errorWithDomain:@"CLSHttpingErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Request timeout"}], NO);
    });
    }); // end dispatch_async(queue)
}

#if __has_include(<Security/SecProtocolOptions.h>)
// HTTPS 且 enableSSLVerification==NO 时使用 C API 创建带"接受任意证书"的 TLS 参数，与 NSURLSession 路径行为一致
- (void)startHttpingWithNetworkFrameworkNoSSLWithHost:(NSString *)host path:(NSString *)path port:(uint16_t)port completion:(void (^)(NSDictionary *finalReportDict, NSError *error))completion
API_AVAILABLE(ios(12.0)) {
    const char *hostC = host.UTF8String;
    const char *portC = [[@(port) stringValue] UTF8String];
    if (!hostC || !portC) {
        NSError *err = [NSError errorWithDomain:@"CLSHttpingErrorDomain" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid host or port"}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([self buildFinalReportDictWithTask:nil error:err], err);
        });
        return;
    }

    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    __block nw_parameters_t params = NULL;
    nw_parameters_configure_protocol_block_t configure_tls = ^(nw_protocol_options_t tls_options) {
        sec_protocol_options_t sec_opts = nw_tls_copy_sec_protocol_options(tls_options);
        if (sec_opts) {
            sec_protocol_options_set_verify_block(sec_opts, ^(sec_protocol_metadata_t metadata, sec_trust_t trust_ref, sec_protocol_verify_complete_t complete) {
                complete(true);  // 关闭校验时接受任意证书，与 NSURLSession didReceiveChallenge 行为一致
            }, queue);
        }
    };
    params = nw_parameters_create_secure_tcp(configure_tls, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    if (!params) {
        NSError *err = [NSError errorWithDomain:@"CLSHttpingErrorDomain" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create TLS parameters"}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([self buildFinalReportDictWithTask:nil error:err], err);
        });
        return;
    }

    NSString *ifName = self.interfaceInfo[@"name"] ?: @"";
    if ([ifName hasPrefix:@"en"]) {
        nw_parameters_set_required_interface_type(params, nw_interface_type_wifi);
        nw_parameters_prohibit_interface_type(params, nw_interface_type_cellular);
    } else if ([ifName hasPrefix:@"pdp_ip"]) {
        nw_parameters_set_required_interface_type(params, nw_interface_type_cellular);
        nw_parameters_prohibit_interface_type(params, nw_interface_type_wifi);
    }

    nw_endpoint_t endpoint = nw_endpoint_create_host(hostC, portC);
    if (!endpoint) {
        params = NULL;
        NSError *err = [NSError errorWithDomain:@"CLSHttpingErrorDomain" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid endpoint"}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([self buildFinalReportDictWithTask:nil error:err], err);
        });
        return;
    }

    __block nw_connection_t c_conn = nw_connection_create(endpoint, params);
    params = NULL;  // 连接已持有 parameters，ARC 下不再持有
    endpoint = NULL;
    if (!c_conn) {
        NSError *err = [NSError errorWithDomain:@"CLSHttpingErrorDomain" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create connection"}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([self buildFinalReportDictWithTask:nil error:err], err);
        });
        return;
    }

    __block BOOL completed = NO;
    __block NSUInteger receivedBytes = 0;
    __block NSInteger statusCode = -2;
    __block CFAbsoluteTime taskStart = CFAbsoluteTimeGetCurrent();
    __weak __typeof(self) weakSelf = self;

    void (^finish)(NSError *, BOOL) = ^(NSError *error, BOOL connectionAlreadyDead) {
        if (completed) return;
        completed = YES;
        nw_connection_t connToCancel = NULL;
        if (c_conn) {
            if (!connectionAlreadyDead) {
                connToCancel = c_conn;
                c_conn = NULL;
                // 避免在 connection 回调栈内同步 cancel 导致崩溃（Enqueued from com.apple.network.connections）
                dispatch_async(queue, ^{
                    if (connToCancel) nw_connection_cancel(connToCancel);
                });
            } else {
                c_conn = NULL;
            }
        }
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.taskStartTime = taskStart;
        strongSelf.receivedBytes = receivedBytes;
        strongSelf.networkResultStatusCode = statusCode;
        NSDictionary *dict = [strongSelf buildFinalReportDictWithTask:nil error:error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(dict, error);
        });
    };

    nw_connection_set_queue(c_conn, queue);
    nw_connection_set_state_changed_handler(c_conn, ^(nw_connection_state_t state, nw_error_t error) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        switch (state) {
            case nw_connection_state_ready: {
                if (strongSelf.connectionReadyTime == 0) {
                    strongSelf.connectionReadyTime = CFAbsoluteTimeGetCurrent();
                }
                if (!strongSelf.resolvedRemoteAddress && @available(iOS 14.0, *)) {
                    nw_path_t path_copy = nw_connection_copy_current_path(c_conn);
                    if (path_copy) {
                        nw_endpoint_t remote_ep = nw_path_copy_effective_remote_endpoint(path_copy);
                        if (remote_ep) {
                            const struct sockaddr *addr = nw_endpoint_get_address(remote_ep);
                            if (addr) {
                                char ipStr[INET6_ADDRSTRLEN];
                                const void *ipPtr = (addr->sa_family == AF_INET)
                                    ? (const void *)&((const struct sockaddr_in *)addr)->sin_addr
                                    : (const void *)&((const struct sockaddr_in6 *)addr)->sin6_addr;
                                if (inet_ntop(addr->sa_family, ipPtr, ipStr, sizeof(ipStr))) {
                                    strongSelf.resolvedRemoteAddress = [NSString stringWithUTF8String:ipStr];
                                }
                            }
                            cls_nw_object_release((__bridge void *)remote_ep);
                        }
                        cls_nw_object_release((__bridge void *)path_copy);
                    }
                }
                NSString *req = [NSString stringWithFormat:@"GET %@ HTTP/1.1\r\nHost: %@\r\nUser-Agent: CLSHttping/2.0.0\r\nConnection: close\r\n\r\n", path, host];
                NSData *reqData = [req dataUsingEncoding:NSUTF8StringEncoding];
                strongSelf.sentBytes = reqData.length;
                dispatch_data_t sendData = dispatch_data_create(reqData.bytes, reqData.length, queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                nw_connection_send(c_conn, sendData, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t sendError) {
                    if (sendError) {
                        finish([NSError errorWithDomain:@"CLSHttpingErrorDomain" code:2000 + (int)sendError userInfo:@{NSLocalizedDescriptionKey: @"Send failed"}], NO);
                        return;
                    }
                    nw_connection_receive(c_conn, 1, 65536, ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t recvError) {
                        if (recvError) {
                            finish([NSError errorWithDomain:@"CLSHttpingErrorDomain" code:2000 + (int)recvError userInfo:@{NSLocalizedDescriptionKey: @"Receive failed"}], NO);
                            return;
                        }
                        if (content && dispatch_data_get_size(content) > 0) {
                            __strong __typeof(weakSelf) strongSelfRecv = weakSelf;
                            if (strongSelfRecv && strongSelfRecv.firstByteArrivalTime == 0) {
                                strongSelfRecv.firstByteArrivalTime = CFAbsoluteTimeGetCurrent();
                            }
                            size_t size = 0;
                            const void *buf = NULL;
                            dispatch_data_t mapped = dispatch_data_create_map(content, &buf, &size);
                            if (buf && size > 0) {
                                receivedBytes += size;
                                if (statusCode == -2) {
                                    NSData *chunk = [NSData dataWithBytes:buf length:size];
                                    NSString *firstLine = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
                                    NSArray *lines = [firstLine componentsSeparatedByString:@"\r\n"];
                                    if (lines.count) {
                                        NSArray *parts = [lines[0] componentsSeparatedByString:@" "];
                                        if (parts.count >= 2) statusCode = [parts[1] integerValue];
                                    }
                                }
                            }
                            (void)mapped;  // 保持映射区域有效直至解析完成
                        }
                        // 成功收到数据后不再 cancel，避免与 connection 自关闭竞争导致崩溃（block_invoke_5）
                        finish(nil, YES);
                    });
                });
                break;
            }
            case nw_connection_state_failed:
                finish(cls_connection_failed_error(error, YES), YES);  // NoSSL 路径仅用于 HTTPS；连接已 failed，不再 cancel
                break;
            case nw_connection_state_cancelled:
                if (!completed) finish([NSError errorWithDomain:@"CLSHttpingErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Connection cancelled"}], YES);
                break;
            default:
                break;
        }
    });
    nw_connection_start(c_conn);

    // timeout 从毫秒转换为纳秒（NoSSL 路径）
    int64_t timeoutInNanoseconds = (int64_t)(self.request.timeout * NSEC_PER_MSEC);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, timeoutInNanoseconds), queue, ^{
        if (!completed) finish([NSError errorWithDomain:@"CLSHttpingErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Request timeout"}], NO);
    });
}
#endif
#endif



- (void)completeWithError:(NSError *)error {
    // 直接生成最终上报字典
    NSDictionary *finalReportDict = [self buildFinalReportDictWithTask:nil error:error];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionHandler) {
            self.completionHandler(finalReportDict, error);
            self.completionHandler = nil;
        }
        if (self.urlSession) {
            [self.urlSession finishTasksAndInvalidate];
        }
    });
}

#pragma mark - NSURLSession Delegates
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    if (!self.request.enableSSLVerification) {
        NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    // ✅ 增强错误日志：输出详细错误信息
    if (error) {
        NSLog(@"[HTTP] 请求失败 - Domain: %@, Code: %ld, Description: %@",
              error.domain, (long)error.code, error.localizedDescription);
        NSLog(@"[HTTP] 请求 URL: %@", task.originalRequest.URL.absoluteString);
        NSLog(@"[HTTP] 网卡接口: %@", self.interfaceInfo[@"name"]);
        
        // 特殊错误：unsupported URL
        if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorUnsupportedURL) {
            NSLog(@"[HTTP] ⚠️ 检测到 unsupported URL 错误，可能原因：");
            NSLog(@"  1. URL Scheme 不支持（应为 http:// 或 https://）");
            NSLog(@"  2. Session 配置限制（allowsCellularAccess/networkServiceType）");
            NSLog(@"  3. 系统网络策略限制");
        }
    }

    // 直接生成最终上报字典
    NSDictionary *finalReportDict = [self buildFinalReportDictWithTask:task error:error];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionHandler) {
            self.completionHandler(finalReportDict, error);
            self.completionHandler = nil;
        }
        [self.urlSession finishTasksAndInvalidate];
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics {
    for (NSURLSessionTaskTransactionMetrics *transaction in metrics.transactionMetrics) {
        [self recordTimingMetrics:transaction];
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveData:(NSData *)data {
    [self.responseData appendData:data];
    self.receivedBytes += data.length;
}

#pragma mark - 指标记录
- (void)recordTimingMetrics:(NSURLSessionTaskTransactionMetrics *)transaction {
    NSMutableDictionary *metrics = [NSMutableDictionary dictionary];
    
    // HTTP 协议版本（iOS 10+）
    if (@available(iOS 10.0, *)) {
        metrics[@"httpProtocol"] = transaction.networkProtocolName ?: @"unknown";
    } else {
        metrics[@"httpProtocol"] = @"unknown";
    }
    
    // DNS耗时
    if (transaction.domainLookupStartDate && transaction.domainLookupEndDate) {
        NSTimeInterval dnsResolutionTime = [transaction.domainLookupEndDate timeIntervalSinceDate:transaction.domainLookupStartDate] * 1000;
        metrics[@"dnsTime"] = [NSString stringWithFormat:@"%.2f", dnsResolutionTime];

        CFAbsoluteTime dnsStartAbsoluteTime = [transaction.domainLookupStartDate timeIntervalSinceReferenceDate];
        NSTimeInterval waitDnsTime = (dnsStartAbsoluteTime - self.taskStartTime) * 1000;
        metrics[@"waitDnsTime"] = [NSString stringWithFormat:@"%.2f", waitDnsTime];

        metrics[@"dnsStart"] = [CLSStringUtils formatDateToMillisecondString:transaction.domainLookupStartDate];
        metrics[@"dnsEnd"] = [CLSStringUtils formatDateToMillisecondString:transaction.domainLookupEndDate];
    }

    // TCP耗时
    if (transaction.connectStartDate) {
        NSTimeInterval tcpTime = 0;
        // HTTPS场景：纯TCP耗时 = SSL开始时间 - TCP开始时间
        if (transaction.secureConnectionStartDate) {
            tcpTime = [transaction.secureConnectionStartDate timeIntervalSinceDate:transaction.connectStartDate] * 1000;
        }
        // HTTP场景：TCP耗时 = 连接结束时间 - TCP开始时间
        else if (transaction.connectEndDate) {
            tcpTime = [transaction.connectEndDate timeIntervalSinceDate:transaction.connectStartDate] * 1000;
        }
        metrics[@"tcpTime"] = [NSString stringWithFormat:@"%.2f", tcpTime];
        metrics[@"connectStart"] = [CLSStringUtils formatDateToMillisecondString:transaction.connectStartDate];
        // TCP结束时间：HTTPS=SSL开始时间，HTTP=connectEndDate
        NSDate *tcpEndDate = transaction.secureConnectionStartDate ?: transaction.connectEndDate;
        metrics[@"connectEnd"] = [CLSStringUtils formatDateToMillisecondString:tcpEndDate];
    } else {
        metrics[@"tcpTime"] = @"0.00";
        metrics[@"connectStart"] = @"";
        metrics[@"connectEnd"] = @"";
    }

    // SSL耗时
    if (transaction.secureConnectionStartDate && transaction.secureConnectionEndDate) {
        NSTimeInterval sslTime = [transaction.secureConnectionEndDate timeIntervalSinceDate:transaction.secureConnectionStartDate] * 1000;
        metrics[@"sslTime"] = [NSString stringWithFormat:@"%.2f", sslTime];
        metrics[@"secureConnectStart"] = [CLSStringUtils formatDateToMillisecondString:transaction.secureConnectionStartDate];
        metrics[@"secureConnectEnd"] = [CLSStringUtils formatDateToMillisecondString:transaction.secureConnectionEndDate];
    }else{
        metrics[@"sslTime"] = @"0.00";
        metrics[@"secureConnectStart"] = @"";
        metrics[@"secureConnectEnd"] = @"";
    }

    // 请求耗时
    if (transaction.requestStartDate && transaction.requestEndDate) {
        NSDate *preparationDate = [NSDate dateWithTimeIntervalSinceReferenceDate:self.taskStartTime];
        metrics[@"callStart"] = [CLSStringUtils formatDateToMillisecondString:preparationDate];
        metrics[@"requestHeaderStart"] = [CLSStringUtils formatDateToMillisecondString:transaction.requestStartDate];
        metrics[@"requestHeaderEnd"] = [CLSStringUtils formatDateToMillisecondString:transaction.requestEndDate];
    }

    // 计算firstByteTime
    if (transaction.secureConnectionEndDate && transaction.responseStartDate) {
        // HTTPS场景：连接建立 = SSL结束时间
        NSTimeInterval firstByteTime = [transaction.responseStartDate timeIntervalSinceDate:transaction.secureConnectionEndDate] * 1000;
        metrics[@"firstByteTime"] = [NSString stringWithFormat:@"%.2f", firstByteTime];
    } else if (transaction.connectEndDate && transaction.responseStartDate) {
        // HTTP场景：连接建立 = TCP结束时间
        NSTimeInterval firstByteTime = [transaction.responseStartDate timeIntervalSinceDate:transaction.connectEndDate] * 1000;
        metrics[@"firstByteTime"] = [NSString stringWithFormat:@"%.2f", firstByteTime];
    } else {
        metrics[@"firstByteTime"] = @"0.00"; // 无有效数据
    }
    
    // 2. 新增allByteTime独立计算（连接建立 → 所有响应）
    if (transaction.secureConnectionEndDate && transaction.responseEndDate) {
        // HTTPS场景
        NSTimeInterval allByteTime = [transaction.responseEndDate timeIntervalSinceDate:transaction.secureConnectionEndDate] * 1000;
        metrics[@"allByteTime"] = [NSString stringWithFormat:@"%.2f", allByteTime];
    } else if (transaction.connectEndDate && transaction.responseEndDate) {
        // HTTP场景
        NSTimeInterval allByteTime = [transaction.responseEndDate timeIntervalSinceDate:transaction.connectEndDate] * 1000;
        metrics[@"allByteTime"] = [NSString stringWithFormat:@"%.2f", allByteTime];
    } else {
        metrics[@"allByteTime"] = @"0.00"; // 无有效数据
    }
    
    // 响应耗时
    if (transaction.responseStartDate && transaction.responseEndDate) {
        metrics[@"callEnd"] = [CLSStringUtils formatDateToMillisecondString:transaction.responseEndDate];
        metrics[@"responseHeadersStart"] = [CLSStringUtils formatDateToMillisecondString:transaction.responseStartDate];
        metrics[@"responseHeaderEnd"] = [CLSStringUtils formatDateToMillisecondString:transaction.responseStartDate];
        metrics[@"responseBodyStart"] = [CLSStringUtils formatDateToMillisecondString:transaction.responseStartDate];
        metrics[@"responseBodyEnd"] = [CLSStringUtils formatDateToMillisecondString:transaction.responseEndDate];
    }

    // 通用字段
    metrics[@"connectionReleased"] = [CLSStringUtils formatDateToMillisecondString:transaction.responseEndDate];
    if (transaction.remoteAddress) metrics[@"remoteAddr"] = transaction.remoteAddress;
    
    NSUInteger sentBytes = transaction.countOfRequestHeaderBytesSent + transaction.countOfRequestBodyBytesSent;
    if (sentBytes != 0) metrics[@"sendBytes"] = @(sentBytes);

    [self.timingMetrics addEntriesFromDictionary:metrics];
}

#pragma mark - 核心：合并结果构建+上报数据清洗为一个函数
- (NSDictionary *)buildFinalReportDictWithTask:(NSURLSessionTask *)task
                                         error:(NSError *)error{
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
    NSMutableDictionary *finalReportDict = [NSMutableDictionary dictionary];
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
    NSTimeInterval totalTime = (endTime - self.processStartTime) * 1000;

    // Network.framework 路径（task 为 nil）无 NSURLSessionTaskMetrics，用 taskStart/end 与首包时间填充 timingMetrics，避免 desc 与时间指标全空
    if (!task && self.taskStartTime > 0) {
        NSDate *startDate = [NSDate dateWithTimeIntervalSinceReferenceDate:self.taskStartTime];
        NSDate *endDate = [NSDate dateWithTimeIntervalSinceReferenceDate:endTime];
        NSString *startStr = [CLSStringUtils formatDateToMillisecondString:startDate];
        NSString *endStr = [CLSStringUtils formatDateToMillisecondString:endDate];
        self.timingMetrics[@"callStart"] = startStr;
        self.timingMetrics[@"callEnd"] = endStr;
        self.timingMetrics[@"connectionReleased"] = endStr;
        // 连接/首包时间：优先首包时间；否则用 connectionReadyTime（TCP+TLS 就绪）；再否则用 start
        NSDate *connectEndDate = startDate;
        NSString *connectEndStr = startStr;
        if (self.firstByteArrivalTime > 0) {
            NSTimeInterval firstByteMs = (self.firstByteArrivalTime - self.taskStartTime) * 1000;
            self.timingMetrics[@"firstByteTime"] = [NSString stringWithFormat:@"%.2f", firstByteMs];
            NSDate *firstByteDate = [NSDate dateWithTimeIntervalSinceReferenceDate:self.firstByteArrivalTime];
            connectEndDate = firstByteDate;
            connectEndStr = [CLSStringUtils formatDateToMillisecondString:firstByteDate];
            self.timingMetrics[@"responseHeadersStart"] = connectEndStr;
            self.timingMetrics[@"responseHeaderEnd"] = connectEndStr;
            self.timingMetrics[@"responseBodyStart"] = connectEndStr;
        } else if (self.connectionReadyTime > 0) {
            connectEndDate = [NSDate dateWithTimeIntervalSinceReferenceDate:self.connectionReadyTime];
            connectEndStr = [CLSStringUtils formatDateToMillisecondString:connectEndDate];
        }
        self.timingMetrics[@"responseBodyEnd"] = endStr;
        self.timingMetrics[@"allByteTime"] = [NSString stringWithFormat:@"%.2f", totalTime];
        self.timingMetrics[@"httpProtocol"] = @"HTTP/1.1";
        
        // ========== tcpTime/sslTime 精准测量方案 ==========
        // 问题：Network.framework 只在连接完全就绪（TCP+TLS）后触发 state_ready，无法分离测量
        // 精准方案：使用 nw_connection_copy_protocol_metadata 获取 TLS 握手信息，推算 TCP 时间
        NSURL *urlForScheme = [NSURL URLWithString:self.request.domain];
        BOOL isHTTPS = urlForScheme && [urlForScheme.scheme.lowercaseString isEqualToString:@"https"];
        if (self.connectionReadyTime > 0 && self.taskStartTime > 0) {
            NSTimeInterval connectMs = (self.connectionReadyTime - self.taskStartTime) * 1000;
            if (connectMs < 0) connectMs = 0;
            
            if (isHTTPS) {
                // HTTPS 场景：尝试从 protocol metadata 获取 TLS 握手时间
                // 如果 tcpReadyTime 已记录（通过 path monitoring），使用精确值
                if (self.tcpReadyTime > 0 && self.tcpReadyTime < self.connectionReadyTime) {
                    NSTimeInterval tcpMs = (self.tcpReadyTime - self.taskStartTime) * 1000;
                    NSTimeInterval sslMs = (self.connectionReadyTime - self.tcpReadyTime) * 1000;
                    if (tcpMs < 0) tcpMs = 0;
                    if (sslMs < 0) sslMs = 0;
                    self.timingMetrics[@"tcpTime"] = [NSString stringWithFormat:@"%.2f", tcpMs];
                    self.timingMetrics[@"sslTime"] = [NSString stringWithFormat:@"%.2f", sslMs];
                } else {
                    // 无法精确测量：整个时间记为 sslTime，tcpTime 为 0（与之前逻辑一致）
                    // 注：这反映了 API 限制，建议使用 NSURLSession 路径获取精确数据
                    self.timingMetrics[@"tcpTime"] = @"0.00";
                    self.timingMetrics[@"sslTime"] = [NSString stringWithFormat:@"%.2f", connectMs];
                }
            } else {
                // HTTP 场景：全部为 TCP 时间
                self.timingMetrics[@"tcpTime"] = [NSString stringWithFormat:@"%.2f", connectMs];
                self.timingMetrics[@"sslTime"] = @"0.00";
            }
        } else {
            self.timingMetrics[@"tcpTime"] = @"0.00";
            self.timingMetrics[@"sslTime"] = @"0.00";
        }
        if (self.sentBytes > 0) {
            self.timingMetrics[@"sendBytes"] = @(self.sentBytes);
        }
        // 补全 desc 其余字段；若有真实 DNS 时间（getaddrinfo 测得）则优先使用
        if (self.dnsStartTime > 0 && self.dnsEndTime > 0) {
            NSDate *dnsStartDate = [NSDate dateWithTimeIntervalSinceReferenceDate:self.dnsStartTime];
            NSDate *dnsEndDate = [NSDate dateWithTimeIntervalSinceReferenceDate:self.dnsEndTime];
            self.timingMetrics[@"dnsStart"] = [CLSStringUtils formatDateToMillisecondString:dnsStartDate];
            self.timingMetrics[@"dnsEnd"] = [CLSStringUtils formatDateToMillisecondString:dnsEndDate];
            NSTimeInterval dnsTimeMs = (self.dnsEndTime - self.dnsStartTime) * 1000;
            self.timingMetrics[@"dnsTime"] = [NSString stringWithFormat:@"%.2f", dnsTimeMs];
            NSTimeInterval waitDnsMs = (self.dnsStartTime - self.processStartTime) * 1000;
            if (waitDnsMs >= 0) self.timingMetrics[@"waitDnsTime"] = [NSString stringWithFormat:@"%.2f", waitDnsMs];
        } else {
            self.timingMetrics[@"dnsStart"] = startStr;
            self.timingMetrics[@"dnsEnd"] = startStr;
            self.timingMetrics[@"dnsTime"] = @"0.00";
        }
        if (self.resolvedRemoteAddress.length > 0) {
            self.timingMetrics[@"remoteAddr"] = self.resolvedRemoteAddress;
        }
        self.timingMetrics[@"connectStart"] = startStr;
        self.timingMetrics[@"connectEnd"] = connectEndStr;
        self.timingMetrics[@"requestHeaderStart"] = startStr;
        self.timingMetrics[@"requestHeaderEnd"] = connectEndStr;
        if (isHTTPS) {
            self.timingMetrics[@"secureConnectStart"] = startStr;
            self.timingMetrics[@"secureConnectEnd"] = connectEndStr;
        }
    }

    // -------------------------- 1. 构建原netOrigin核心字段 --------------------------
    NSString *remoteAddr = self.timingMetrics[@"remoteAddr"] ?: @"";
    NSURL *requestURL = [NSURL URLWithString:self.request.domain];
    NSString *domain = requestURL.host ?: @"";
    
    // HTTP状态码处理（task 为 nil 时使用 networkResultStatusCode，如 Network.framework 路径）
    NSInteger statusCode = -2; // 无响应默认值
    if (response) {
        statusCode = (response.statusCode >= 100 && response.statusCode <= 599) ? response.statusCode : -1;
    } else if (self.networkResultStatusCode >= 100 && self.networkResultStatusCode <= 599) {
        statusCode = self.networkResultStatusCode;
    }
    
    // 时间戳统一计算
    NSTimeInterval startDateMs = self.taskStartTime * 1000;
    
    // 带宽计算（避免除0）
    double bandwidth = self.receivedBytes / MAX((totalTime / 1000), 0.001);
    
    // 错误信息处理（增强逻辑）
    NSInteger errCode = 0;
    NSString *errMsg = @"";
    BOOL hasError = NO;  // 标记是否有错误
    
    if (error) {
        // 场景1：网络错误（超时、连接失败等）
        hasError = YES;
        if ([error.domain isEqualToString:NSURLErrorDomain]) {
            errCode = 2000 + error.code;  // 网络错误基础码 2000 + NSURLError code
            errMsg = [NSString stringWithFormat:@"Network error: %@", error.localizedDescription];
        } else if ([error.domain isEqualToString:@"CLSHttpingErrorDomain"]) {
            // 自定义错误（超时=-1, 无效URL=-2）
            errCode = error.code;
            errMsg = error.localizedDescription ?: @"";
        } else {
            // 其他未知错误
            errCode = 3000 + error.code;
            errMsg = [NSString stringWithFormat:@"Unknown error: %@", error.localizedDescription];
        }
    } else if (statusCode >= 400) {
        // 场景2：HTTP错误状态码（4xx/5xx）
        hasError = YES;
        errCode = 1000 + statusCode;  // HTTP错误基础码 1000 + statusCode
        errMsg = [NSString stringWithFormat:@"HTTP %ld", (long)statusCode];
    } else if (statusCode == -2) {
        // 场景3：无响应
        hasError = YES;
        errCode = -3;
        errMsg = @"No response";
    } else if (statusCode >= 200 && statusCode < 400) {
        // 场景4：成功（2xx/3xx）- 不设置错误字段
        hasError = NO;
    } else {
        // 场景5：异常状态码
        hasError = YES;
        errCode = -4;
        errMsg = [NSString stringWithFormat:@"Invalid status code: %ld", (long)statusCode];
    }

    // 基础网络指标（原netOrigin）
    NSMutableDictionary *netOrigin = [@{
        @"method": @"http",
        @"url": self.request.domain ?: @"",
        @"trace_id": CLSIdGenerator.generateTraceId,
        @"appKey": self.request.appKey ?: @"",
        @"host_ip": remoteAddr,
        @"domain": domain,
        @"remoteAddr": remoteAddr,
        @"interface": self.interfaceInfo[@"type"] ?: @"",
        @"src": @"app",
        @"sdkVer": [CLSStringUtils getSdkVersion],
        @"sdkBuild": [CLSNetworkUtils getSDKBuildTime] ?: @"",
        @"ts": [NSString stringWithFormat:@"%.2f", startDateMs],
        @"waitDnsTime": self.timingMetrics[@"waitDnsTime"] ?: @"0.00",
        @"dnsTime": self.timingMetrics[@"dnsTime"] ?: @"0.00",
        @"tcpTime": self.timingMetrics[@"tcpTime"] ?: @"0.00",
        @"sslTime": self.timingMetrics[@"sslTime"] ?: @"0.00",
        @"firstByteTime": self.timingMetrics[@"firstByteTime"] ?: @"0.00",
        @"sendBytes": self.timingMetrics[@"sendBytes"] ?: @0,
        @"receiveBytes": @(self.receivedBytes),
        @"allByteTime": self.timingMetrics[@"allByteTime"] ?: @"0.00",
        @"bandwidth": [NSString stringWithFormat:@"%.2f", bandwidth],
        @"requestTime": [NSString stringWithFormat:@"%.2f", totalTime],
        @"httpCode": @(statusCode),
        @"httpProtocol": self.timingMetrics[@"httpProtocol"] ?: @"unknown",
        @"interface_ip": self.interfaceInfo[@"ip"] ?: @"",
        @"interface_type": self.interfaceInfo[@"type"] ?: @"",
        @"interface_family": self.interfaceInfo[@"family"] ?: @""
    } mutableCopy];
    
    // 仅在有错误时添加错误字段
    if (hasError) {
        netOrigin[@"errCode"] = @(errCode);
        netOrigin[@"errMsg"] = errMsg;
    }
    
    // -------------------------- 2. 合并原resultDict的基础字段 --------------------------
    finalReportDict[@"pageName"] = self.request.pageName ?: @"";
    finalReportDict[@"totalTime"] = [NSString stringWithFormat:@"%.2f", totalTime];
    
    // -------------------------- 3. 合并扩展字段 --------------------------
    // 构建headers（response 为空时仅填接口信息）
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (response && response.allHeaderFields) {
        [response.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            NSString *lowercaseKey = [key lowercaseString];
            headers[lowercaseKey] = obj;
        }];
    }
    headers[@"x-network-interface"] = self.interfaceInfo[@"name"] ?: @"";
    if (self.interfaceInfo[@"ip"]) {
        headers[@"x-source-ip"] = self.interfaceInfo[@"ip"];
    }
    
    // 构建时间描述
    NSDictionary *timeDesc = @{
        @"callStart": self.timingMetrics[@"callStart"] ?: @"",
        @"dnsStart": self.timingMetrics[@"dnsStart"] ?: @"",
        @"dnsEnd": self.timingMetrics[@"dnsEnd"] ?: @"",
        @"connectStart": self.timingMetrics[@"connectStart"] ?: @"",
        @"secureConnectStart": self.timingMetrics[@"secureConnectStart"] ?: @"",
        @"secureConnectEnd": self.timingMetrics[@"secureConnectEnd"] ?: @"",
        @"connectionAcquired": self.timingMetrics[@"connectEnd"] ?: @"",
        @"requestHeaderStart": self.timingMetrics[@"requestHeaderStart"] ?: @"",
        @"requestHeaderEnd": self.timingMetrics[@"requestHeaderEnd"] ?: @"",
        @"responseHeadersStart": self.timingMetrics[@"responseHeadersStart"] ?: @"",
        @"responseHeaderEnd": self.timingMetrics[@"responseHeaderEnd"] ?: @"",
        @"responseBodyStart": self.timingMetrics[@"responseBodyStart"] ?: @"",
        @"responseBodyEnd": self.timingMetrics[@"responseBodyEnd"] ?: @"",
        @"connectionReleased": self.timingMetrics[@"connectionReleased"] ?: @"",
        @"callEnd": self.timingMetrics[@"callEnd"] ?: @""
    };
    
    // 网络信息
    NSDictionary *netInfo = [CLSNetworkUtils buildEnhancedNetworkInfoWithInterfaceType:self.interfaceInfo[@"type"]
                                                                   networkAppId:self.networkAppId
                                                                          appKey:self.appKey
                                                                            uin:self.uin
                                                                        endpoint:self.endPoint
                                                                   interfaceDNS:self.interfaceInfo[@"dns"]];

    // 合并到最终字典
    finalReportDict[@"headers"] = headers;
    finalReportDict[@"desc"] = timeDesc;
    finalReportDict[@"netInfo"] = netInfo ?: @{};
    finalReportDict[@"detectEx"] = self.request.detectEx ?: @{};
    finalReportDict[@"userEx"] = [[ClsNetworkDiagnosis sharedInstance] getUserEx] ?: @{};  // 从全局获取
    
    // -------------------------- 4. 合并netOrigin所有字段（平铺，也可保留层级，按需调整） --------------------------
    [finalReportDict addEntriesFromDictionary:netOrigin];
    
    // -------------------------- 5. 统一清洗字段（确保JSON兼容） --------------------------
    [finalReportDict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([obj isKindOfClass:[NSString class]]) {
            finalReportDict[key] = [CLSStringUtils sanitizeString:obj] ?: @"";
        } else if ([obj isKindOfClass:[NSNumber class]]) {
            finalReportDict[key] = [CLSStringUtils sanitizeNumber:obj] ?: @0;
        } else if ([obj isKindOfClass:[NSDictionary class]]) {
            finalReportDict[key] = [CLSStringUtils sanitizeDictionary:obj] ?: @{};
        }
    }];

    return [finalReportDict copy];
}

#pragma mark - 对外暴露的启动方法
- (void)start:(CompleteCallback)complate {
    // 参数合法性校验
    NSError *validationError = nil;
    if (![CLSRequestValidator validateHttpRequest:self.request error:&validationError]) {
        NSLog(@"❌ HTTP探测参数校验失败: %@", validationError.localizedDescription);
        if (complate) {
            CLSResponse *errorResponse = [CLSResponse complateResultWithContent:@{
                @"error": @"INVALID_PARAMETER",
                @"errMsg": validationError.localizedDescription,
                @"errCode": @(validationError.code)
            }];
            complate(errorResponse);
        }
        return;
    }
    
    // ⚠️ HTTPing 不支持多次探测，单次探测后立即上报（无论成功失败）
    NSLog(@"✅ HTTP探测参数: timeout=%dms, size=%d bytes", self.request.timeout, self.request.size);
    
    NSArray<NSDictionary *> *availableInterfaces = [CLSNetworkUtils getAvailableInterfacesForType];
    if (availableInterfaces.count == 0) {
        NSLog(@"HTTPing 无可用网卡接口（网卡可能被禁用）");
        CLSResponse *emptyResult = [CLSResponse complateResultWithContent:@{}];
        if (complate) complate(emptyResult);
        return;
    }
    
    // ✅ 多网卡模式：使用串行队列 + 信号量等待每个探测完成（参考 TCPing 实现）
    // ✅ 单网卡模式：for 循环只执行一次，无需后台队列
    if (self.request.enableMultiplePortsDetect && availableInterfaces.count > 1) {
        // 多网卡模式：在后台队列中串行执行每个网卡的探测
        dispatch_queue_t detectionQueue = dispatch_queue_create("com.cls.httping.multiInterface", DISPATCH_QUEUE_SERIAL);
        dispatch_async(detectionQueue, ^{
            for (NSDictionary *currentInterface in availableInterfaces) {
                NSDictionary *capturedInterface = [currentInterface copy];  // 捕获接口信息
                NSString *interfaceName = capturedInterface[@"name"] ?: @"未知";
                NSLog(@"🚀 HTTPing 开始探测网卡：%@", interfaceName);
                
                // 创建信号量，等待异步探测完成
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                
                // 执行单次探测
                // ✅ 创建 extraProvider 并传递接口名称
                CLSExtraProvider *extraProvider = [[CLSExtraProvider alloc] init];
                [extraProvider setExtra:@"network.interface.name" value:capturedInterface[@"name"] ?: @""];
                
                CLSSpanBuilder *builder = [[CLSSpanBuilder builder] initWithName:@"network_diagnosis"
                                                                       provider:[[CLSSpanProviderDelegate alloc] initWithExtraProvider:extraProvider]];
                [builder setURL:self.request.domain];
                [builder setpageName:self.request.pageName];
                if (self.request.traceId) {
                    [builder setTraceId:self.request.traceId];
                }
                
                // 为每个网卡创建独立实例
                CLSMultiInterfaceHttping *instanceToUse = [[CLSMultiInterfaceHttping alloc] initWithRequest:self.request];
                instanceToUse.topicId = self.topicId;
                instanceToUse.networkAppId = self.networkAppId;
                instanceToUse.appKey = self.appKey;
                instanceToUse.uin = self.uin;
                instanceToUse.region = self.region;
                instanceToUse.endPoint = self.endPoint;
                
                [instanceToUse startHttpingWithCompletion:capturedInterface completion:^(NSDictionary *finalReportDict, NSError *error) {
                    // 记录探测结果（无论成功失败）
                    NSInteger httpCode = [finalReportDict[@"httpCode"] integerValue];
                    BOOL isHttpSuccess = (httpCode >= 200 && httpCode < 400);
                    
                    if (!error && isHttpSuccess) {
                        NSLog(@"✅ HTTP Ping 成功 - 网卡:%@ HTTP %ld", interfaceName, (long)httpCode);
                    } else {
                        NSLog(@"❌ HTTP Ping 失败 - 网卡:%@ HTTP %ld, Error: %@",
                              interfaceName, (long)httpCode, error.localizedDescription ?: @"连接失败");
                    }
                    
                    // 立即上报结果（使用当前 self 的 topicId 与回调）
                    NSDictionary *d = [builder report:self.topicId reportData:finalReportDict];
                    
                    // 封装为 CLSResponse 返回
                    CLSResponse *completionResult = [CLSResponse complateResultWithContent:d ?: @{}];
                    
                    // 回调返回结果（每个网卡完成都会回调一次，这是预期行为）
                    NSLog(@"📤 HTTPing 网卡 %@ 探测完成，调用回调", interfaceName);
                    if (complate) {
                        complate(completionResult);
                    }
                    
                    // ✅ 释放信号量，允许下一个网卡开始探测
                    dispatch_semaphore_signal(semaphore);
                }];
                
                // ✅ 等待当前网卡探测完成（阻塞后台线程）
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                NSLog(@"✅ HTTPing 网卡 %@ 探测已完成，准备下一个", interfaceName);
            }
            
            NSLog(@"✅ HTTPing 所有网卡探测完成");
        });
    } else {
        // 单网卡模式：直接在主线程执行（只探测第一个网卡）
        for (NSDictionary *currentInterface in availableInterfaces) {
            NSLog(@"interface:%@", currentInterface);
            
            // 执行单次探测
            // ✅ 创建 extraProvider 并传递接口名称
            CLSExtraProvider *extraProvider = [[CLSExtraProvider alloc] init];
            [extraProvider setExtra:@"network.interface.name" value:currentInterface[@"name"] ?: @""];
            
            CLSSpanBuilder *builder = [[CLSSpanBuilder builder] initWithName:@"network_diagnosis"
                                                                   provider:[[CLSSpanProviderDelegate alloc] initWithExtraProvider:extraProvider]];
            [builder setURL:self.request.domain];
            [builder setpageName:self.request.pageName];
            if (self.request.traceId) {
                [builder setTraceId:self.request.traceId];
            }
            
            // 单网卡模式使用 self（不创建新实例）
            CLSMultiInterfaceHttping *instanceToUse = self;
            
            NSString *interfaceName = currentInterface[@"name"] ?: @"未知";
            NSLog(@"🚀 HTTPing 开始探测网卡：%@", interfaceName);
            
            [instanceToUse startHttpingWithCompletion:currentInterface completion:^(NSDictionary *finalReportDict, NSError *error) {
                // 记录探测结果（无论成功失败）
                NSInteger httpCode = [finalReportDict[@"httpCode"] integerValue];
                BOOL isHttpSuccess = (httpCode >= 200 && httpCode < 400);
                
                if (!error && isHttpSuccess) {
                    NSLog(@"✅ HTTP Ping 成功 - 网卡:%@ HTTP %ld", interfaceName, (long)httpCode);
                } else {
                    NSLog(@"❌ HTTP Ping 失败 - 网卡:%@ HTTP %ld, Error: %@",
                          interfaceName, (long)httpCode, error.localizedDescription ?: @"连接失败");
                }
                
                // 立即上报结果（使用当前 self 的 topicId 与回调）
                NSDictionary *d = [builder report:self.topicId reportData:finalReportDict];
                
                // 封装为 CLSResponse 返回
                CLSResponse *completionResult = [CLSResponse complateResultWithContent:d ?: @{}];
                
                // 回调返回结果（每个网卡完成都会回调一次，这是预期行为）
                NSLog(@"📤 HTTPing 网卡 %@ 探测完成，调用回调", interfaceName);
                if (complate) {
                    complate(completionResult);
                }
            }];
            
            // 单网卡模式：只执行第一个接口
            break;
        }
    }
}

@end

