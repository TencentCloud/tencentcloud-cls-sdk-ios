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
    
    // 设置超时控制
    [self setupTimeoutTimer];
    
    // 启动异步Ping测试
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (NSUInteger i = 0; i < self.request.maxTimes && !_isCompleted; i++) {
            [self performTcpPing];
        }
        
        // 所有请求完成且未超时的情况下主动完成
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
    if (connect(sock, (struct sockaddr *)addr, sizeof(struct sockaddr)) < 0) {
        struct timeval tv;
        fd_set wset;
        tv.tv_sec = 3; // 超时时间
        tv.tv_usec = 0;
        FD_ZERO(&wset);
        FD_SET(sock, &wset);
        int n = select(sock + 1, NULL, &wset, NULL, &tv);
        if (n < 0 || n == 0) {
            close(sock);
            return -1;
        }
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
        if (host == NULL || host->h_addr == NULL) return;
        addr.sin_addr = *(struct in_addr *)host->h_addr;
    }
    
    // 计算耗时
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    int result = [self connect:&addr];
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
    NSTimeInterval latency = (endTime - startTime) * 1000;
    
    // 统计结果
    if (result == 0) {
        [self.latencies addObject:@(latency)];
        self.successCount++;
    } else {
        self.failureCount++;
    }
}

- (NSString *)resolvedIP {
    return self.request.domain; // 简化版直接返回host，可根据实际需求扩展DNS解析逻辑
}

- (void)setupTimeoutTimer {
    [self cancelTimeoutTimer];
    
    __weak typeof(self) weakSelf = self;
    _timeoutTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                         dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    
    dispatch_source_set_timer(_timeoutTimer,
                             dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.request.timeout * NSEC_PER_SEC)),
                             DISPATCH_TIME_FOREVER, 0);
    
    dispatch_source_set_event_handler(_timeoutTimer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleTimeout];
    });
    
    dispatch_resume(_timeoutTimer);
}

- (void)handleTimeout {
    _isCompleted = YES;
    [self cancelTimeoutTimer];
    
    NSError *error = [NSError errorWithDomain:kTcpPingErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Request timeout"}];
    [self completePingWithError:error];
}

- (void)completePingWithError:(NSError *)error {
    if (_isCompleted) return;
    _isCompleted = YES;
    
    [self cancelTimeoutTimer];
    
    // 直接构建上报数据（不再生成CLSMultiInterfaceTcpingResult）
    NSDictionary *reportData = [self buildReportDataFromTcpPingResult];
    
    // 切回主线程回调
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionHandler) {
            self.completionHandler(reportData, error);
            self.completionHandler = nil;
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
- (NSDictionary *)buildReportDataFromTcpPingResult {
    // 1. 计算核心统计值
    NSNumber *minLatency = [self.latencies valueForKeyPath:@"@min.self"] ?: @0;
    NSNumber *maxLatency = [self.latencies valueForKeyPath:@"@max.self"] ?: @0;
    NSNumber *avgLatency = [self.latencies valueForKeyPath:@"@avg.self"] ?: @0;
    NSNumber *stddev = [self calculateStdDev] ?: @0;
    double totalLatency = [[self.latencies valueForKeyPath:@"@sum.self"] doubleValue];
    
    // 2. 时间戳（毫秒级）
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970] * 1000;
    
    // 3. 构建网络信息
    NSDictionary *netInfo = [CLSNetworkUtils buildEnhancedNetworkInfoWithInterfaceType:self.interface[@"type"]
                                                                           networkAppId:self.networkAppId
                                                                                  appKey:self.appKey
                                                                                    uin:self.uin
                                                                                endpoint:self.endPoint
                                                                           interfaceDNS:self.interface[@"dns"]];
    
    // 4. 构建上报数据（一步到位，无中间对象）
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
        @"loss": [CLSStringUtils sanitizeNumber:@(self.failureCount)] ?: @0,
        @"latency_min": [CLSStringUtils sanitizeNumber:minLatency] ?: @0,
        @"latency_max": [CLSStringUtils sanitizeNumber:maxLatency] ?: @0,
        @"latency": [CLSStringUtils sanitizeNumber:avgLatency] ?: @0,
        @"stddev": [CLSStringUtils sanitizeNumber:stddev] ?: @0,
        @"responseNum": [CLSStringUtils sanitizeNumber:@(self.successCount)] ?: @0,
        @"exceptionNum": [CLSStringUtils sanitizeNumber:@(self.failureCount)] ?: @0,
        @"bindFailed": [CLSStringUtils sanitizeNumber:@(self.bindFailedCount)] ?: @0,
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
    NSArray<NSDictionary *> *availableInterfaces = [CLSNetworkUtils getAvailableInterfacesForType];
    for (NSDictionary *currentInterface in availableInterfaces) {
        NSLog(@"availableInterfaces:%@", currentInterface);
        CLSSpanBuilder *builder = [[CLSSpanBuilder builder] initWithName:@"network_diagnosis" provider:[[CLSSpanProviderDelegate alloc] init]];
        [builder setURL:self.request.domain];
        
        [self startPingWithCompletion:currentInterface completion:^(NSDictionary *reportData, NSError *error) {
            // 封装为CLSResponse，兼容原有回调协议
            CLSResponse *completeResult = [CLSResponse complateResultWithContent:reportData ?: @{}];
            if (complete) {
                complete(completeResult);
            }
            [builder report:self.topicId reportData:reportData ?: @{}];
        }];
        
        if (!self.request.enableMultiplePortsDetect) {
            break;
        }
    }
}

@end
