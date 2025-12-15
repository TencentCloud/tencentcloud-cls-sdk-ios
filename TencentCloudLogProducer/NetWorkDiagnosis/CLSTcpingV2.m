//
//  CLSTcping.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/15.
//
// CLSTcpPing.m
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

@implementation CLSMultiInterfaceTcpingResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _netType = @"http";
        _eventType = @"net_d";
        _success = NO;
    }
    return self;
}

@end

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
                     completion:(void (^)(CLSMultiInterfaceTcpingResult *, NSError *))completion {
    self.completionHandler = completion;
    _isCompleted = NO;
    
    // 重置状态
    self.successCount = 0;
    self.failureCount = 0;
    self.bindFailedCount = 0;
    [self.latencies removeAllObjects];
    
    //设置网卡
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
    
    int on = 1;
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
    setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, (char *)&on, sizeof(on));

    struct timeval timeout;
    timeout.tv_sec = (long)self.request.timeout;
    timeout.tv_usec = 10;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, (char *)&timeout, sizeof(timeout));
    int flags;
    flags = fcntl(sock, F_GETFL, 0);
    if (flags == -1)
    {
        close(sock);
        return -1;
    }
    flags |= O_NONBLOCK;
    if (fcntl(sock, F_SETFL, flags) == -1)
    {
        close(sock);
        return -1;
    }
    if (connect(sock, (struct sockaddr *)addr, sizeof(struct sockaddr)) < 0) {
        struct timeval tv;
        fd_set wset;
        tv.tv_sec = 3; //timeout
        tv.tv_usec = 0;
        FD_ZERO(&wset);
        FD_SET(sock, &wset);
        int n = select(sock + 1, NULL, &wset, NULL, &tv);
        if (n < 0)
        {
            close(sock);
            return -1;
        }
        else if (n == 0)
        {
            close(sock);
            return -1;
        }
    }
    flags &= ~ O_NONBLOCK;
    fcntl(sock,F_SETFL, flags);
    close(sock);
    return 0;
    
}

- (void)performTcpPing {
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(self.request.port);
    const char *hostaddr = [self.request.domain UTF8String];
    if (hostaddr == NULL) {
        hostaddr = "\0";
    }
    addr.sin_addr.s_addr = inet_addr(hostaddr);
    if (addr.sin_addr.s_addr == INADDR_NONE) {
        struct hostent *host = gethostbyname(hostaddr);
        if (host == NULL || host->h_addr == NULL) {
            return;
        }
        addr.sin_addr = *(struct in_addr *)host->h_addr;
    }
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    int result = [self connect:&addr];
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
    NSTimeInterval latency = (endTime - startTime) * 1000;
    if (result == 0) {
        [self.latencies addObject:@(latency)];
        self.successCount++;
    } else {
        self.failureCount++;
    }
}

- (NSString *)resolvedIP {
    return self.request.domain; // 简化版直接返回host
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
    
    NSError *error = [NSError errorWithDomain:@"CLSTcpingErrorDomain"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Request timeout"}];
    [self completePingWithError:error];
}

- (void)completePingWithError:(NSError *)error {
    if (_isCompleted) return;
    _isCompleted = YES;
    
    [self cancelTimeoutTimer];
    
    CLSMultiInterfaceTcpingResult *result = [self buildResult];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionHandler) {
            self.completionHandler(result, error);
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


- (CLSMultiInterfaceTcpingResult *)buildResult {
    CLSMultiInterfaceTcpingResult *result = [[CLSMultiInterfaceTcpingResult alloc] init];
    result.netType = @"tcpping";
    result.eventType = @"net_d";
    result.success = self.failureCount == 0;
    result.totalTime = [[self.latencies valueForKeyPath:@"@sum.self"] doubleValue];
    
    // 构建netOrigin
    result.netOrigin = [self buildNetOrigin];
    
    // 构建netInfo
    result.netInfo = [self buildEnhancedNetworkInfo];
    
    result.detectEx = self.request.detectEx;
    result.userEx = self.request.userEx;
    
    return result;
}

- (NSDictionary *)buildNetOrigin {
    NSNumber *minLatency = [self.latencies valueForKeyPath:@"@min.self"] ?: @0;
    NSNumber *maxLatency = [self.latencies valueForKeyPath:@"@max.self"] ?: @0;
    NSNumber *avgLatency = [self.latencies valueForKeyPath:@"@avg.self"] ?: @0;
    NSNumber *stddev = [self calculateStdDev] ?: @0;
    
    return @{
        @"host": self.request.domain ?: @"",
        @"method": @"tcpping",
        @"trace_id": CLSIdGenerator.generateTraceId,
        @"appKey": self.request.appKey ?: @"",
        @"host_ip": [self resolvedIP] ?: @"",
        @"port": @(self.request.port),
        @"interface": self.interface[@"type"] ? self.interface[@"type"] : @"",
        @"count": @(self.request.maxTimes),
        @"total": @([[self.latencies valueForKeyPath:@"@sum.self"] doubleValue]),
        @"loss": @(self.failureCount),
        @"latency_min": minLatency,
        @"latency_max": maxLatency,
        @"latency": avgLatency,
        @"stddev": stddev,
        @"responseNum": @(self.successCount),
        @"exceptionNum": @(self.failureCount),
        @"bindFailed": @(self.bindFailedCount),
        @"src": @"app",
        @"netInfo": [self buildEnhancedNetworkInfo],
        @"detectEx": self.request.detectEx ?: @{},
        @"userEx": self.request.userEx ?: @{}
    };
}

- (NSDictionary *)buildEnhancedNetworkInfo {
    NSMutableDictionary *networkInfo = [CLSNetworkUtils getNetworkEnvironmentInfo:self.interface[@"type"] networkAppId:self.networkAppId appKey:self.appKey uin:self.uin endpoint:self.region];
    return [networkInfo copy];
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

- (NSDictionary *)buildReportDataFromTcpPingResult:(CLSMultiInterfaceTcpingResult *)result {
    // 获取当前时间戳
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970] * 1000;
    
    // 构建基础信息 - 确保所有值都是JSON兼容类型
    NSMutableDictionary *reportData = [NSMutableDictionary dictionaryWithDictionary:@{
        @"host": [CLSStringUtils sanitizeString:result.netOrigin[@"host"]] ?: @"",
        @"method": @"tcpping",
        @"trace_id": [CLSStringUtils sanitizeString:result.netOrigin[@"trace_id"]] ?: @"",
        @"appKey": [CLSStringUtils sanitizeString:result.netOrigin[@"appKey"]] ?: @"",
        @"host_ip": [CLSStringUtils sanitizeString:result.netOrigin[@"host_ip"]] ?: @"",
        @"port": [CLSStringUtils sanitizeNumber:result.netOrigin[@"port"]] ?: @0,
        @"interface": [CLSStringUtils sanitizeString:result.netOrigin[@"interface"]] ?: @"unknown",
        @"count": [CLSStringUtils sanitizeNumber:result.netOrigin[@"count"]] ?: @0,
        @"total": [CLSStringUtils sanitizeNumber:result.netOrigin[@"total"]] ?: @0,
        @"loss": [CLSStringUtils sanitizeNumber:result.netOrigin[@"loss"]] ?: @0,
        @"latency_min": [CLSStringUtils sanitizeNumber:result.netOrigin[@"latency_min"]] ?: @0,
        @"latency_max": [CLSStringUtils sanitizeNumber:result.netOrigin[@"latency_max"]] ?: @0,
        @"latency": [CLSStringUtils sanitizeNumber:result.netOrigin[@"latency"]] ?: @0,
        @"stddev": [CLSStringUtils sanitizeNumber:result.netOrigin[@"stddev"]] ?: @0,
        @"responseNum": [CLSStringUtils sanitizeNumber:result.netOrigin[@"responseNum"]] ?: @0,
        @"exceptionNum": [CLSStringUtils sanitizeNumber:result.netOrigin[@"exceptionNum"]] ?: @0,
        @"bindFailed": [CLSStringUtils sanitizeNumber:result.netOrigin[@"bindFailed"]] ?: @0,
        @"src": @"app",
        @"timestamp": @(timestamp),
        @"startDate": @(timestamp)
    }];
    reportData[@"netInfo"] = [CLSStringUtils sanitizeDictionary:result.netInfo];
    return [reportData copy];
}

- (void)start:(CLSTcpRequest *) request complate:(CompleteCallback)complate {
    
    NSArray<NSDictionary *> *availableInterfaces = [CLSNetworkUtils getAvailableInterfacesForType];
    
    for (NSDictionary *currentInterface in availableInterfaces) {
        NSLog(@"availableInterfaces:%@", currentInterface);
        CLSSpanBuilder *builder = [[CLSSpanBuilder builder] initWithName:@"network_diagnosis" provider:[[CLSSpanProviderDelegate alloc] init]];
        [builder setURL:request.domain];
        CLSMultiInterfaceTcping *tcpPing = [[CLSMultiInterfaceTcping alloc] initWithRequest:request];
        [tcpPing startPingWithCompletion:currentInterface completion:^(CLSMultiInterfaceTcpingResult *result, NSError *error) {
            NSDictionary *reportData = [self buildReportDataFromTcpPingResult:result];
            CLSResponse *complateResult = [CLSResponse complateResultWithContent:reportData];
            if (complate) {
                complate(complateResult);
            }
            [builder report:self.topicId reportData:reportData];

        }];
    }

}

@end
