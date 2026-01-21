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
#import <netinet/in.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import "CLSTcpingV2.h"
#import "CLSRequestValidator.h"
#import "CLSNetworkUtils.h"
#import "CLSIdGenerator.h"
#import "netinet/tcp.h"
#import "CLSSPanBuilder.h"
#import "CLSCocoa.h"
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

- (int)connect:(struct sockaddr_in *)addr {
    int sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock == -1) {
        return errno;
    }
    
    // 绑定指定网卡
    NSString *interfaceName = self.interface[@"name"];
    NSString *interfaceIP = self.interface[@"ip"];
    if (interfaceName && ![interfaceName isEqualToString:@"unknown"] && interfaceIP) {
        struct sockaddr_in localAddr;
        memset(&localAddr, 0, sizeof(localAddr));
        localAddr.sin_family = AF_INET;
        localAddr.sin_port = 0; // 系统自动分配源端口
        inet_pton(AF_INET, interfaceIP.UTF8String, &localAddr.sin_addr);
        
        if (bind(sock, (struct sockaddr *)&localAddr, sizeof(localAddr)) == -1) {
            NSLog(@"Bind to interface %@ (IP: %@) failed: %s", interfaceName, interfaceIP, strerror(errno));
            self.bindFailedCount++;
            close(sock);
            return -1;
        } else {
            NSLog(@"Successfully bound to interface: %@ (IP: %@)", interfaceName, interfaceIP);
        }
    }
    
    // 设置socket参数
    int on = 1;
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
    setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, (char *)&on, sizeof(on));

    // 设置超时
    struct timeval timeout;
    timeout.tv_sec = (long)self.request.timeout;
    timeout.tv_usec = 10;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, (char *)&timeout, sizeof(timeout));
    
    // 设置非阻塞
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
    
    // 非阻塞connect
    int connectResult = connect(sock, (struct sockaddr *)addr, sizeof(struct sockaddr));
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
    
    // 单次探测超时（与HTTP Ping保持一致）
    dispatch_source_set_timer(_timeoutTimer,
                             dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.request.timeout * NSEC_PER_SEC)),
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
        @"userEx": [CLSStringUtils sanitizeDictionary:self.request.userEx] ?: @{}
    }];
    
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
    // 参数合法性校验
    NSError *validationError = nil;
    if (![CLSRequestValidator validateTcpRequest:self.request error:&validationError]) {
        NSLog(@"❌ TCP探测参数校验失败: %@", validationError.localizedDescription);
        if (complete) {
            CLSResponse *errorResponse = [CLSResponse complateResultWithContent:@{
                @"error": @"参数校验失败",
                @"error_message": validationError.localizedDescription,
                @"error_code": @(validationError.code)
            }];
            complete(errorResponse);
        }
        return;
    }
    
    // maxTimes 表示最大尝试次数（包含首次尝试）
    int maxRetries = self.request.maxTimes;
    NSLog(@"✅ TCP探测参数: port=%ld, maxRetries=%d, timeout=%ds, size=%d bytes", 
          (long)self.request.port, maxRetries, self.request.timeout, self.request.size);
    
    NSArray<NSDictionary *> *availableInterfaces = [CLSNetworkUtils getAvailableInterfacesForType];
    for (NSDictionary *currentInterface in availableInterfaces) {
        NSLog(@"availableInterfaces:%@", currentInterface);
        
        // 使用串行队列和信号量实现同步重试逻辑
        dispatch_queue_t retryQueue = dispatch_queue_create("com.tencent.cls.tcpping.retry", DISPATCH_QUEUE_SERIAL);
        
        dispatch_async(retryQueue, ^{
            __block BOOL hasSucceeded = NO;
            
            // 执行 maxRetries 次尝试（首次 + 失败后的重试）
            for (int i = 0; i < maxRetries && !hasSucceeded; i++) {
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                
                int attemptCount = i + 1;
                NSLog(@"🔄 TCP Ping 尝试 %d/%d", attemptCount, maxRetries);
                
                CLSSpanBuilder *builder = [[CLSSpanBuilder builder] initWithName:@"network_diagnosis" provider:[[CLSSpanProviderDelegate alloc] init]];
                [builder setURL:self.request.domain];
                [builder setpageName:self.request.pageName];
                
                [self startPingWithCompletion:currentInterface completion:^(NSDictionary *reportData, NSError *error) {
                    // ✅ TCP Ping 判断成功标准：无错误且有成功响应
                    NSInteger responseNum = [reportData[@"responseNum"] integerValue];
                    NSInteger totalCount = [reportData[@"count"] integerValue];
                    
                    if (!error && responseNum > 0) {
                        hasSucceeded = YES;
                        NSLog(@"✅ TCP Ping 成功（第 %d 次尝试）- 响应 %ld/%ld", 
                              attemptCount, (long)responseNum, (long)totalCount);
                    } else {
                        NSLog(@"❌ TCP Ping 失败（第 %d 次尝试）- 响应 %ld/%ld, Error: %@", 
                              attemptCount, (long)responseNum, (long)totalCount, 
                              error.localizedDescription ?: @"无响应");
                    }
                    
                    // 上报并获取返回字典
                    NSDictionary *d = [builder report:self.topicId reportData:reportData ?: @{}];
                    
                    // 封装为CLSResponse，兼容原有回调协议
                    CLSResponse *completeResult = [CLSResponse complateResultWithContent:d ?: @{}];
                    if (complete) {
                        complete(completeResult);
                    }
                    
                    // 释放信号量
                    dispatch_semaphore_signal(semaphore);
                }];
                
                // 等待当前尝试完成
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            }
        });
        
        if (!self.request.enableMultiplePortsDetect) {
            break;
        }
    }
}

@end
