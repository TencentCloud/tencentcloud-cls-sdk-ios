//
//  CLSTcping.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/15.
//

#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <net/if.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import "CLSTcpingV2.h"
#import "CLSRequestValidator.h"
#import "CLSNetworkUtils.h"
#import "CLSIdGenerator.h"
#import "netinet/tcp.h"
#import "CLSSPanBuilder.h"
#import "CLSCocoa.h"
#import "ClsNetworkDiagnosis.h"  // 引入以获取全局 userEx
#import "CLSStringUtils.h"

// 常量抽取（统一维护）
static NSString *const kTcpPingMethod = @"tcpping";
static NSString *const kSrcApp = @"app";
static NSString *const kInterfaceDefault = @"unknown";
static NSString *const kTcpPingErrorDomain = @"CLSTcpingErrorDomain";

@implementation CLSMultiInterfaceTcping

- (instancetype)initWithRequest:(CLSTcpRequest *)request {
    self = [super init];
    if (self) {
        _request = request;
        _latencies = [NSMutableArray array];
        _isCompleted = NO;
        _interface = @{};
    }
    return self;
}

- (void)startPingWithCompletion:(NSDictionary *)currentInterface
                     completion:(void (^)(NSDictionary *reportData, NSError *error))completion {
    self.completionHandler = completion;
    _isCompleted = NO;
    
    // 重置状态
    self.successCount = 0;
    self.failureCount = 0;
    self.bindFailedCount = 0;
    [self.latencies removeAllObjects];
    
    // 设置网卡
    self.interface = [currentInterface copy];
    
    // ✅ 移除外层定时器，只依赖 Socket 层的 select() 超时控制
    // Socket 的 select(sock, ..., timeout) 已提供精准的超时机制
    // 外层定时器会与重试逻辑冲突，导致 _isCompleted 提前设置，阻止重试
    
    // 执行单次TCP Ping（依赖 Socket 超时，外层控制 maxTimes 重试）
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self performTcpPing];
        
        // 探测完成（成功或 Socket 层超时），主动回调
        if (!_isCompleted) {
            [self completePingWithError:nil];
        }
    });
}

#pragma mark - 通用连接（IPv4/IPv6 + 接口绑定）
/// 按地址族创建 socket、绑定接口（IP_BOUND_IF / IPV6_BOUND_IF）并连接，与 Ping/MTR 一致
- (int)connectWithAddr:(const struct sockaddr *)addr addrLen:(socklen_t)addrLen {
    if (!addr || addrLen < sizeof(struct sockaddr)) {
        return -1;
    }
    int family = addr->sa_family;
    int sock = socket(family, SOCK_STREAM, IPPROTO_TCP);
    if (sock == -1) {
        return errno;
    }

    // 绑定指定网卡（参考 Ping/MTR：IPv4 用 IP_BOUND_IF，IPv6 用 IPV6_BOUND_IF）
    NSString *interfaceName = self.interface[@"name"];
    NSNumber *indexNum = self.interface[@"index"];
    unsigned int interfaceIndex = 0;
    if (interfaceName && ![interfaceName isEqualToString:@"unknown"] && indexNum && [indexNum isKindOfClass:[NSNumber class]]) {
        NSInteger tempIndex = [indexNum integerValue];
        if (tempIndex > 0) {
            interfaceIndex = (unsigned int)tempIndex;
        }
    }
    if (interfaceIndex == 0 && interfaceName && interfaceName.length > 0 && ![interfaceName isEqualToString:@"unknown"]) {
        interfaceIndex = if_nametoindex(interfaceName.UTF8String);
    }
    if (interfaceIndex > 0) {
        if (family == AF_INET6) {
#if defined(IPV6_BOUND_IF)
            if (setsockopt(sock, IPPROTO_IPV6, IPV6_BOUND_IF, &interfaceIndex, sizeof(interfaceIndex)) < 0) {
                NSLog(@"TCP bind to interface %@ (index %u) IPv6 failed: %s", interfaceName, interfaceIndex, strerror(errno));
                self.bindFailedCount++;
                close(sock);
                return -1;
            }
            NSLog(@"Successfully bound to interface: %@ (index %u) IPv6", interfaceName ?: @"", interfaceIndex);
#else
            (void)interfaceName;
#endif
        } else {
#if defined(IP_BOUND_IF)
            if (setsockopt(sock, IPPROTO_IP, IP_BOUND_IF, &interfaceIndex, sizeof(interfaceIndex)) < 0) {
                NSLog(@"TCP bind to interface %@ (index %u) failed: %s", interfaceName, interfaceIndex, strerror(errno));
                self.bindFailedCount++;
                close(sock);
                return -1;
            }
            NSLog(@"Successfully bound to interface: %@ (index %u)", interfaceName ?: @"", interfaceIndex);
#else
            // 兜底：无 IP_BOUND_IF 时使用 bind(IP)（仅 IPv4）
            NSString *interfaceIP = self.interface[@"ip"];
            if (interfaceIP) {
                struct sockaddr_in localAddr;
                memset(&localAddr, 0, sizeof(localAddr));
                localAddr.sin_family = AF_INET;
                localAddr.sin_port = 0;
                inet_pton(AF_INET, interfaceIP.UTF8String, &localAddr.sin_addr);
                if (bind(sock, (struct sockaddr *)&localAddr, sizeof(localAddr)) == -1) {
                    NSLog(@"Bind to interface %@ (IP: %@) failed: %s", interfaceName, interfaceIP, strerror(errno));
                    self.bindFailedCount++;
                    close(sock);
                    return -1;
                }
            }
#endif
        }
    }

    // 设置socket参数
    int on = 1;
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
    setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, (char *)&on, sizeof(on));

    // timeout 从毫秒转换为 timeval 结构体（秒和微秒）
    struct timeval timeout;
    timeout.tv_sec = (long)(self.request.timeout / 1000);  // 秒部分
    timeout.tv_usec = (long)((self.request.timeout % 1000) * 1000);  // 微秒部分
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, (char *)&timeout, sizeof(timeout));

    int flags = fcntl(sock, F_GETFL, 0);
    if (flags == -1) {
        close(sock);
        return -1;
    }
    flags |= O_NONBLOCK;
    if (fcntl(sock, F_SETFL, flags) == -1) {
        close(sock);
        return -1;
    }

    int connectResult = connect(sock, addr, addrLen);
    if (connectResult < 0) {
        // 非阻塞connect正常应该返回-1且errno=EINPROGRESS
        if (errno != EINPROGRESS) {
            // 如果不是EINPROGRESS，说明连接立即失败（如网络不可达）
            NSLog(@"TCP connect immediate failure, errno: %d (%s), port: %d", errno, strerror(errno), self.request.port);
            close(sock);
            return -1;
        }
        
        // errno=EINPROGRESS，使用select等待连接完成
        struct timeval tv;
        fd_set wset, eset;
        tv.tv_sec = self.request.timeout; // 超时时间
        tv.tv_usec = 0;
        FD_ZERO(&wset);
        FD_ZERO(&eset);
        FD_SET(sock, &wset);
        FD_SET(sock, &eset);  // 同时监听异常
        
        int n = select(sock + 1, NULL, &wset, &eset, &tv);
        if (n < 0) {
            NSLog(@"TCP select failed, errno: %d (%s), port: %d", errno, strerror(errno), self.request.port);
            close(sock);
            return -1;
        }
        if (n == 0) {
            NSLog(@"TCP select timeout, port: %d", self.request.port);
            close(sock);
            return -1;
        }
        
        // select返回>0，检查是writeable还是exception
        if (FD_ISSET(sock, &eset)) {
            NSLog(@"TCP socket exception occurred, port: %d", self.request.port);
            close(sock);
            return -1;
        }
        
        // 检查socket错误状态（核心修复）
        int error = 0;
        socklen_t len = sizeof(error);
        if (getsockopt(sock, SOL_SOCKET, SO_ERROR, &error, &len) == 0) {
            if (error != 0) { // error≠0 表示连接失败（如端口不存在、连接拒绝）
                NSLog(@"TCP connect failed, error: %s (errno: %d, port: %d)", strerror(error), error, self.request.port);
                close(sock);
                return -1;
            }
        } else {
            NSLog(@"getsockopt failed, errno: %d (%s), port: %d", errno, strerror(errno), self.request.port);
            close(sock);
            return -1;
        }
        
        // 连接成功
        NSLog(@"TCP connect succeeded after select, port: %d", self.request.port);
    } else {
        // connectResult >= 0，立即连接成功（罕见情况，通常只发生在本地连接）
        NSLog(@"TCP connect succeeded immediately (unusual), port: %d", self.request.port);
    }
    
    // 恢复阻塞模式
    flags &= ~O_NONBLOCK;
    fcntl(sock, F_SETFL, flags);
    close(sock);
    return 0;
}

/// IPv4 兼容包装，供 performTcpPing 等原有路径使用
- (int)connect:(struct sockaddr_in *)addr {
    return [self connectWithAddr:(const struct sockaddr *)addr addrLen:sizeof(struct sockaddr_in)];
}

- (void)performTcpPing {
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(self.request.port);
    
    // 解析域名/IP
    const char *hostaddr = [self.request.domain UTF8String];
    if (hostaddr == NULL) hostaddr = "\0";
    addr.sin_addr.s_addr = inet_addr(hostaddr);
    
    if (addr.sin_addr.s_addr == INADDR_NONE) {
        struct hostent *host = gethostbyname(hostaddr);
        if (host == NULL || host->h_addr == NULL) {
            NSLog(@"⚠️ TCP Ping: DNS resolution failed for %s, port: %d", hostaddr, self.request.port);
            self.failureCount++;
            return;
        }
        addr.sin_addr = *(struct in_addr *)host->h_addr;
    }
    
    // 解析成功后记录IP
    char ipStr[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &(addr.sin_addr), ipStr, INET_ADDRSTRLEN);
    
    // 计算耗时
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    int result = [self connect:&addr];
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
    NSTimeInterval latency = (endTime - startTime) * 1000;
    
    // 统计结果（增加详细日志）
    if (result == 0) {
        [self.latencies addObject:@(latency)];
        self.successCount++;
        NSLog(@"✅ TCP Ping SUCCESS: %s:%d, latency: %.2fms", ipStr, self.request.port, latency);
    } else {
        self.failureCount++;
        NSLog(@"❌ TCP Ping FAILED: %s:%d, latency: %.2fms, result: %d", ipStr, self.request.port, latency, result);
    }
}

- (NSString *)resolvedIP {
    return self.request.domain; // 简化版直接返回host，可根据实际需求扩展DNS解析逻辑
}

- (void)setupTimeoutTimer {
    [self cancelTimeoutTimer];
    
    _timeoutTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                         dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    
    // 单次探测超时（timeout 从毫秒转换为纳秒）
    int64_t timeoutInNanoseconds = (int64_t)(self.request.timeout * NSEC_PER_MSEC);
    dispatch_source_set_timer(_timeoutTimer,
                             dispatch_time(DISPATCH_TIME_NOW, timeoutInNanoseconds),
                             DISPATCH_TIME_FOREVER,
                             0.1 * NSEC_PER_SEC);  // leeway: 100ms，提高定时器精度
    
    // 使用 __unsafe_unretained 代替 __weak（MRC 环境）
    __unsafe_unretained typeof(self) unretainedSelf = self;
    dispatch_source_set_event_handler(_timeoutTimer, ^{
        [unretainedSelf handleTimeout];
    });
    
    dispatch_resume(_timeoutTimer);
}

- (void)handleTimeout {
    NSLog(@"⏰ TCP Ping 超时触发: domain=%@, port=%d, timeout=%ds",
          self.request.domain, self.request.port, self.request.timeout);
    
    _isCompleted = YES;
    [self cancelTimeoutTimer];
    
    NSError *error = [NSError errorWithDomain:kTcpPingErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Request timeout"}];
    [self completePingWithError:error];
}

- (void)completePingWithError:(NSError *)error {
    if (_isCompleted) {
        NSLog(@"⚠️ TCP Ping 已完成，忽略重复回调");
        return;
    }
    _isCompleted = YES;
    
    [self cancelTimeoutTimer];
    
    NSLog(@"📊 TCP Ping 结束: domain=%@, success=%lu, failure=%lu, bindFailed=%lu, error=%@",
          self.request.domain,
          (unsigned long)self.successCount,
          (unsigned long)self.failureCount,
          (unsigned long)self.bindFailedCount,
          error.localizedDescription ?: @"无");
    
    // 直接构建上报数据（不再生成CLSMultiInterfaceTcpingResult）
    NSDictionary *reportData = [self buildReportDataFromTcpPingResultWithError:error];
    
    // 切回主线程回调
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionHandler) {
            NSLog(@"✅ TCP Ping 回调执行: domain=%@, port=%d", self.request.domain, self.request.port);
            self.completionHandler(reportData, error);
            self.completionHandler = nil;
        } else {
            NSLog(@"⚠️ TCP Ping 回调为 nil，无法执行");
        }
    });
}

- (void)cancelTimeoutTimer {
    if (_timeoutTimer) {
        dispatch_source_cancel(_timeoutTimer);
        _timeoutTimer = nil;
    }
}

// 核心方法：直接基于原始状态构建上报数据（移除buildResult后，所有逻辑集中在此）
- (NSDictionary *)buildReportDataFromTcpPingResultWithError:(NSError *)error {
    // 1. 计算核心统计值
    NSNumber *minLatency = [self.latencies valueForKeyPath:@"@min.self"] ?: @0;
    NSNumber *maxLatency = [self.latencies valueForKeyPath:@"@max.self"] ?: @0;
    NSNumber *avgLatency = [self.latencies valueForKeyPath:@"@avg.self"] ?: @0;
    NSNumber *stddev = [self calculateStdDev] ?: @0;
    double totalLatency = [[self.latencies valueForKeyPath:@"@sum.self"] doubleValue];
    
    // 2. 计算丢包率（范围：0.0～1.0）
    NSUInteger totalAttempts = self.successCount + self.failureCount;
    double lossRate = totalAttempts > 0 ? (double)self.failureCount / (double)totalAttempts : 0.0;
    // 确保范围在 [0.0, 1.0]
    lossRate = MAX(0.0, MIN(1.0, lossRate));
    
    // 3. 时间戳（毫秒级）
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970] * 1000;
    
    // 4. 错误信息处理（增强逻辑）
    NSInteger errorCode = 0;
    NSString *errorMessage = @"";
    
    if (error) {
        // 场景1：有明确错误对象（超时、网络错误等）
        if ([error.domain isEqualToString:kTcpPingErrorDomain]) {
            errorCode = error.code;  // 超时=-1, 其他自定义错误
            errorMessage = error.localizedDescription ?: @"";
        } else {
            // 其他域的错误
            errorCode = 3000 + error.code;
            errorMessage = [NSString stringWithFormat:@"Unknown error: %@", error.localizedDescription];
        }
    } else {
        // 场景2：无错误对象，根据统计信息判断
        if (totalAttempts == 0) {
            // 未进行任何探测
            errorCode = -5;
            errorMessage = @"No attempts made";
        } else if (self.bindFailedCount > 0 && self.successCount == 0) {
            // 所有尝试都因 bind 失败
            errorCode = -20;
            errorMessage = [NSString stringWithFormat:@"Interface bind failed (%lu attempts)", (unsigned long)self.bindFailedCount];
        } else if (lossRate >= 1.0) {
            // 完全丢包
            errorCode = -11;
            errorMessage = [NSString stringWithFormat:@"Total packet loss (0/%lu)", (unsigned long)totalAttempts];
        } else if (lossRate > 0.0) {
            // 部分丢包
            errorCode = -10;
            errorMessage = [NSString stringWithFormat:@"Partial packet loss (%.1f%%, %lu/%lu)", 
                            lossRate * 100, (unsigned long)self.successCount, (unsigned long)totalAttempts];
        } else {
            // 成功（无丢包）
            errorCode = 0;
            errorMessage = [NSString stringWithFormat:@"Success (%lu/%lu)", 
                            (unsigned long)self.successCount, (unsigned long)totalAttempts];
        }
    }
    
    // 5. 构建网络信息
    NSDictionary *netInfo = [CLSNetworkUtils buildEnhancedNetworkInfoWithInterfaceType:self.interface[@"type"]
                                                                           networkAppId:self.networkAppId
                                                                                  appKey:self.appKey
                                                                                    uin:self.uin
                                                                                endpoint:self.endPoint
                                                                           interfaceDNS:self.interface[@"dns"]];
    
    // 6. 构建上报数据（一步到位，无中间对象）
    NSMutableDictionary *reportData = [NSMutableDictionary dictionaryWithDictionary:@{
        // 基础信息
        @"host": [CLSStringUtils sanitizeString:self.request.domain] ?: @"",
        @"method": kTcpPingMethod,
        @"trace_id": [CLSStringUtils sanitizeString:CLSIdGenerator.generateTraceId] ?: @"",
        @"appKey": [CLSStringUtils sanitizeString:self.request.appKey] ?: @"",
        @"host_ip": [CLSStringUtils sanitizeString:[self resolvedIP]] ?: @"",
        @"port": [CLSStringUtils sanitizeNumber:@(self.request.port)] ?: @0,
        @"interface": [CLSStringUtils sanitizeString:self.interface[@"type"]] ?: kInterfaceDefault,
        // 统计信息
        @"count": [CLSStringUtils sanitizeNumber:@(self.request.maxTimes)] ?: @0,
        @"total": [CLSStringUtils sanitizeNumber:@(totalLatency)] ?: @0,
        @"loss": [CLSStringUtils sanitizeNumber:@(lossRate)] ?: @0,  // 修复：使用丢包率（0～1）
        @"latency_min": [CLSStringUtils sanitizeNumber:minLatency] ?: @0,
        @"latency_max": [CLSStringUtils sanitizeNumber:maxLatency] ?: @0,
        @"latency": [CLSStringUtils sanitizeNumber:avgLatency] ?: @0,
        @"stddev": [CLSStringUtils sanitizeNumber:stddev] ?: @0,
        @"responseNum": [CLSStringUtils sanitizeNumber:@(self.successCount)] ?: @0,
        @"exceptionNum": [CLSStringUtils sanitizeNumber:@(self.failureCount)] ?: @0,
        @"bindFailed": [CLSStringUtils sanitizeNumber:@(self.bindFailedCount)] ?: @0,
        // 错误信息
        @"err_code": @(errorCode),
        @"error_message": errorMessage,
        // 通用字段
        @"src": kSrcApp,
        @"timestamp": @(timestamp),
        @"netInfo": [CLSStringUtils sanitizeDictionary:netInfo] ?: @{},
        @"detectEx": [CLSStringUtils sanitizeDictionary:self.request.detectEx] ?: @{},
        @"userEx": [CLSStringUtils sanitizeDictionary:[[ClsNetworkDiagnosis sharedInstance] getUserEx]] ?: @{}  // 从全局获取
    }];
    
    return [reportData copy];
}

#pragma mark - 单次探测方法（用于多次汇总）
/// 执行单次 TCP 探测（不重置全局计数器）；按接口 family 解析 IPv4/IPv6 并绑定对应接口（IP_BOUND_IF / IPV6_BOUND_IF）
- (void)performSingleProbeWithInterface:(NSDictionary *)currentInterface
                             completion:(void (^)(BOOL success, NSTimeInterval latency, NSError *error))completion {
    self.interface = [currentInterface copy];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        const char *host = [self.request.domain UTF8String];
        if (!host || host[0] == '\0') {
            NSError *error = [NSError errorWithDomain:kTcpPingErrorDomain code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid host"}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, 0, error); });
            return;
        }
        NSString *portStr = [@(self.request.port) stringValue];
        struct addrinfo hints;
        memset(&hints, 0, sizeof(hints));
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;
        hints.ai_protocol = IPPROTO_TCP;
        // 按接口 family 优先解析 IPv6 或 IPv4，与 Ping/MTR 一致
        NSString *ifFamily = currentInterface[@"family"];
        if ([ifFamily isEqualToString:@"IPv6"]) {
            hints.ai_family = AF_INET6;
        } else {
            hints.ai_family = AF_INET;
        }

        struct addrinfo *res = NULL;
        int gai = getaddrinfo(host, [portStr UTF8String], &hints, &res);
        if (gai != 0 || res == NULL || res->ai_addr == NULL) {
            NSLog(@"⚠️ TCP Ping: DNS resolution failed for %s, port: %d (getaddrinfo: %s)", host, self.request.port, gai_strerror(gai));
            NSError *error = [NSError errorWithDomain:kTcpPingErrorDomain code:-2 userInfo:@{NSLocalizedDescriptionKey: @"DNS resolution failed"}];
            if (res) freeaddrinfo(res);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, 0, error); });
            return;
        }

        CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
        int result = [self connectWithAddr:res->ai_addr addrLen:res->ai_addrlen];
        freeaddrinfo(res);
        CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
        NSTimeInterval latency = (endTime - startTime) * 1000;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (result == 0) {
                completion(YES, latency, nil);
            } else {
                NSError *error = [NSError errorWithDomain:kTcpPingErrorDomain code:result userInfo:@{NSLocalizedDescriptionKey: @"TCP connect failed"}];
                completion(NO, latency, error);
            }
        });
    });
}

#pragma mark - 汇总上报数据构建
/// 构建多次探测汇总后的上报数据
- (NSDictionary *)buildAggregatedReportDictForProbeCount:(NSUInteger)totalProbes {
    // ===== 1. 计算延迟统计（仅基于成功的探测）=====
    double minLatency = 0.0;
    double maxLatency = 0.0;
    double avgLatency = 0.0;
    double stddev = 0.0;
    double totalLatency = 0.0;
    
    if (self.latencies.count > 0) {
        minLatency = [[self.latencies valueForKeyPath:@"@min.self"] doubleValue];
        maxLatency = [[self.latencies valueForKeyPath:@"@max.self"] doubleValue];
        avgLatency = [[self.latencies valueForKeyPath:@"@avg.self"] doubleValue];
        stddev = [[self calculateStdDev] doubleValue];
        totalLatency = [[self.latencies valueForKeyPath:@"@sum.self"] doubleValue];
    }
    
    // ===== 2. 计算丢包相关指标 =====
    // count: 探测次数（用户设置的 maxTimes）
    // responseNum: 响应次数（成功次数）
    // exceptionNum: 异常数（失败次数，包含超时、连接失败等）
    // loss: 丢包数量（不是丢包率！）= 失败次数
    NSUInteger count = totalProbes;
    NSUInteger responseNum = self.successCount;
    NSUInteger exceptionNum = self.failureCount;
    NSUInteger loss = self.failureCount;  // 丢包数量 = 失败次数
    
    // ===== 3. 构建网络信息 =====
    NSDictionary *netInfo = [CLSNetworkUtils buildEnhancedNetworkInfoWithInterfaceType:self.interface[@"type"]
                                                                           networkAppId:self.networkAppId
                                                                                  appKey:self.appKey
                                                                                    uin:self.uin
                                                                                endpoint:self.endPoint
                                                                           interfaceDNS:self.interface[@"dns"]];
    
    // ===== 4. 时间戳（毫秒级）=====
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970] * 1000;
    
    // ===== 5. 构建上报数据 =====
    NSMutableDictionary *reportData = [NSMutableDictionary dictionaryWithDictionary:@{
        // 基础信息
        @"host": [CLSStringUtils sanitizeString:self.request.domain] ?: @"",
        @"method": kTcpPingMethod,
        @"trace_id": [CLSStringUtils sanitizeString:CLSIdGenerator.generateTraceId] ?: @"",
        @"appKey": [CLSStringUtils sanitizeString:self.request.appKey] ?: @"",
        @"host_ip": [CLSStringUtils sanitizeString:[self resolvedIP]] ?: @"",
        @"port": [CLSStringUtils sanitizeNumber:@(self.request.port)] ?: @0,
        @"interface": [CLSStringUtils sanitizeString:self.interface[@"type"]] ?: kInterfaceDefault,
        
        // ⚠️ 核心统计字段（注意字段含义！）
        @"count": @(count),                    // 探测次数（总共探测了多少次）
        @"total": @(totalLatency),             // 总延迟（所有成功探测的延迟之和，单位ms）
        @"loss": @(loss),                      // 丢包数量（失败次数，不是丢包率！）
        @"latency_min": @(minLatency),         // 最小延迟（ms）
        @"latency_max": @(maxLatency),         // 最大延迟（ms）
        @"latency": @(avgLatency),             // 平均延迟（ms）
        @"stddev": @(stddev),                  // 延迟标准差（ms）
        @"responseNum": @(responseNum),        // 响应次数（成功次数）
        @"exceptionNum": @(exceptionNum),      // 异常数（失败次数）
        @"bindFailed": @(self.bindFailedCount), // 绑定失败次数
        
        // 错误信息（根据汇总结果判断）
        @"err_code": @(responseNum > 0 ? 0 : -11),  // 有成功则0，否则-11（完全失败）
        @"error_message": responseNum > 0 ? [NSString stringWithFormat:@"Success (%lu/%lu)", (unsigned long)responseNum, (unsigned long)count] 
                                          : [NSString stringWithFormat:@"All failed (0/%lu)", (unsigned long)count],
        
        // 通用字段
        @"src": kSrcApp,
        @"timestamp": @(timestamp),
        @"netInfo": [CLSStringUtils sanitizeDictionary:netInfo] ?: @{},
        @"detectEx": [CLSStringUtils sanitizeDictionary:self.request.detectEx] ?: @{},
        @"userEx": [CLSStringUtils sanitizeDictionary:[[ClsNetworkDiagnosis sharedInstance] getUserEx]] ?: @{}
    }];
    
    NSLog(@"📊 TCP Ping 汇总上报: count=%lu, responseNum=%lu, loss=%lu, avgLatency=%.2fms, total=%.2fms", 
          (unsigned long)count, (unsigned long)responseNum, (unsigned long)loss, avgLatency, totalLatency);
    
    return [reportData copy];
}

- (NSNumber *)calculateStdDev {
    if (self.latencies.count == 0) return @0;
    
    double mean = [[self.latencies valueForKeyPath:@"@avg.self"] doubleValue];
    double sumOfSquaredDifferences = 0.0;
    
    for (NSNumber *latency in self.latencies) {
        double difference = [latency doubleValue] - mean;
        sumOfSquaredDifferences += difference * difference;
    }
    
    double variance = sumOfSquaredDifferences / self.latencies.count;
    return @(sqrt(variance));
}

- (void)start:(CompleteCallback)complete {
    // ⚠️ 重要：maxTimes 表示固定探测次数（无论成功失败都探测 N 次）
    int totalProbes = self.request.maxTimes;
    NSLog(@"✅ TCP探测参数: port=%ld, totalProbes=%d（固定探测次数）, timeout=%dms（单次超时）", 
          (long)self.request.port, totalProbes, self.request.timeout);
    
    NSArray<NSDictionary *> *availableInterfaces = [CLSNetworkUtils getAvailableInterfacesForType];
    for (NSDictionary *currentInterface in availableInterfaces) {
        NSLog(@"availableInterfaces:%@", currentInterface);
        
        // 使用串行队列执行多次探测
        dispatch_queue_t probeQueue = dispatch_queue_create("com.tencent.cls.tcpping.probe", DISPATCH_QUEUE_SERIAL);
        
        dispatch_async(probeQueue, ^{
            // ===== 重置全局汇总数据（每个接口独立统计）=====
            [self.latencies removeAllObjects];
            self.successCount = 0;
            self.failureCount = 0;
            self.bindFailedCount = 0;
            
            // ===== 执行 totalProbes 次探测（无论成功失败都继续）=====
            for (int i = 0; i < totalProbes; i++) {
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                
                int probeIndex = i + 1;
                NSLog(@"🔄 TCP Ping 探测 %d/%d", probeIndex, totalProbes);
                
                // 执行单次探测（注意：这里会重置内部计数，所以需要在外层汇总）
                [self performSingleProbeWithInterface:currentInterface completion:^(BOOL success, NSTimeInterval latency, NSError *error) {
                    if (success) {
                        // 成功：记录延迟
                        [self.latencies addObject:@(latency)];
                        self.successCount++;
                        NSLog(@"✅ TCP Ping 成功（%d/%d）- 延迟 %.2fms", probeIndex, totalProbes, latency);
                    } else {
                        // 失败：仅计数
                        self.failureCount++;
                        NSLog(@"❌ TCP Ping 失败（%d/%d）- Error: %@", probeIndex, totalProbes, error.localizedDescription ?: @"连接失败");
                    }
                    
                    // 释放信号量（继续下一次探测）
                    dispatch_semaphore_signal(semaphore);
                }];
                
                // 等待当前探测完成
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            }
            
            // ===== 所有探测完成，构建汇总结果并上报 =====
            NSLog(@"📊 TCP Ping 汇总: 总次数=%d, 成功=%lu, 失败=%lu, bind失败=%lu", 
                  totalProbes, (unsigned long)self.successCount, (unsigned long)self.failureCount, (unsigned long)self.bindFailedCount);
            
            NSDictionary *aggregatedResult = [self buildAggregatedReportDictForProbeCount:totalProbes];
            
            // 上报汇总结果
            CLSSpanBuilder *builder = [[CLSSpanBuilder builder] initWithName:@"network_diagnosis" 
                                                                   provider:[[CLSSpanProviderDelegate alloc] init]];
            [builder setURL:self.request.domain];
            [builder setpageName:self.request.pageName];
            if (self.request.traceId) {
                [builder setTraceId:self.request.traceId];
            }
            
            NSDictionary *reportDict = [builder report:self.topicId reportData:aggregatedResult];
            CLSResponse *completionResult = [CLSResponse complateResultWithContent:reportDict ?: @{}];
            
            // 回调返回汇总结果（切回主线程）
            if (complete) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    complete(completionResult);
                });
            }
        });
        
        if (!self.request.enableMultiplePortsDetect) {
            break;
        }
    }
}

@end
