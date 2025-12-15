//
//  CLSPing.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/16.
//

#import <Foundation/Foundation.h>
#import "CLSPingV2.h"
#import "CLSNetworkUtils.h"
#import <netinet/in.h>
#import <arpa/inet.h>
#import <netdb.h>
#import "CLSIdGenerator.h"
#import "CLSSPanBuilder.h"
#import "CLSCocoa.h"

@implementation CLSMultiInterfacePingResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _netType = @"ping";
        _eventType = @"net_d";
        _success = NO;
    }
    return self;
}

@end


@implementation CLSMultiInterfacePing

- (instancetype)initWithConfiguration:(CLSPingRequest *)request {
    self = [super init];
    if (self) {
        _request = request;
        _latencies = [NSMutableArray array];
        _interfaceInfo = @{};
        _isCompleted = NO;
    }
    return self;
}

- (int)connect:(struct sockaddr_in *)addr{
    int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    if (sock == -1) {
        return errno;
    }
    NSString *interfacename = self.interfaceInfo[@"name"];
    if (interfacename && ![interfacename isEqualToString:@"unknown"]) {
         // 获取指定接口的IP地址
         NSString *sourceIP = [CLSNetworkUtils getIPAddressForInterface:interfacename];
         if (sourceIP) {
             struct sockaddr_in localAddr;
             memset(&localAddr, 0, sizeof(localAddr));
             localAddr.sin_family = AF_INET;
             localAddr.sin_port = 0; // 系统自动分配源端口
             inet_pton(AF_INET, sourceIP.UTF8String, &localAddr.sin_addr);
             
             if (bind(sock, (struct sockaddr *)&localAddr, sizeof(localAddr)) == -1) {
                 NSLog(@"Bind to interface %@ (IP: %@) failed: %s", interfacename, sourceIP, strerror(errno));
                 self.bindFailedCount++;
                 close(sock);
                 return -1;
             } else {
                 NSLog(@"Successfully bound to interface: %@ (IP: %@)", interfacename, sourceIP);
             }
         } else {
             NSLog(@"🟡 Could not get IP for interface: %@, using default route", interfacename);
         }
     }

    int index = 0;
    int r = 0;
    uint16_t identifier = (uint16_t)arc4random();
    int ttl = 0;
    int size = 0;
    int loss = 0;
    struct timeval timeout;
    timeout.tv_sec = (long)self.request.timeout;
    timeout.tv_usec = 10;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout));
    int result = [CLSNetworkUtils ping:&addr seq:index identifier:identifier sock:sock ttl:&ttl size:&size];
    close(sock);
    return result;
}

- (void)performPing {
    
    const char *hostaddr = [self.request.domain UTF8String];
    if (hostaddr == NULL) {
        hostaddr = "\0";
    }
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(30002);
    addr.sin_addr.s_addr = inet_addr(hostaddr);
    if (addr.sin_addr.s_addr == INADDR_NONE) { //无效的地址
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

- (NSString *)resolveHostToIP:(NSString *)host {
//    const char *hostname = [host UTF8String];
//    struct hostent *host_entry = gethostbyname(hostname);
//    
//    if (host_entry == NULL) {
//        return host; // 如果解析失败，返回原始host
//    }
//    
//    struct in_addr ​**addr_list = (struct in_addr ​**)host_entry->h_addr_list;
//    if (addr_list[0] != NULL) {
//        char *ip_address = inet_ntoa(*addr_list[0]);
//        return [NSString stringWithUTF8String:ip_address];
//    }
    
    return host;
}

- (NSTimeInterval)extractLatencyFromPingOutput:(NSString *)output {
    // 解析ping输出中的时间值（参考Linux脚本的解析方法）[1,2](@ref)
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        if ([line containsString:@"time="]) {
            NSRange timeRange = [line rangeOfString:@"time="];
            NSRange msRange = [line rangeOfString:@" ms"];
            if (timeRange.location != NSNotFound && msRange.location != NSNotFound) {
                NSRange numberRange = NSMakeRange(timeRange.location + timeRange.length,
                                                msRange.location - (timeRange.location + timeRange.length));
                NSString *timeString = [line substringWithRange:numberRange];
                return [timeString doubleValue];
            }
        }
    }
    return 0;
}

- (CLSMultiInterfacePingResult *)buildPingResult {
    CLSMultiInterfacePingResult *result = [[CLSMultiInterfacePingResult alloc] init];
    result.netType = @"ping";
    result.eventType = @"net_d";
    result.success = (_failureCount == 0);
    result.totalTime = [[_latencies valueForKeyPath:@"@sum.self"] doubleValue];
    
    // 构建netOrigin
    result.netOrigin = [self buildNetOrigin];
    
    // 构建netInfo
    result.netInfo = [self buildEnhancedNetworkInfo];
    
    result.detectEx = self.request.detectEx ?: @{};
    result.userEx = self.request.userEx ?: @{};
    
    return result;
}

- (NSDictionary *)buildNetOrigin {
    NSNumber *minLatency = [_latencies valueForKeyPath:@"@min.self"] ?: @0;
    NSNumber *maxLatency = [_latencies valueForKeyPath:@"@max.self"] ?: @0;
    NSNumber *avgLatency = [_latencies valueForKeyPath:@"@avg.self"] ?: @0;
    NSNumber *stddev = [self calculateStdDev] ?: @0;
    
    double lossRate = self.request.maxTimes > 0 ? (double)_failureCount / self.request.maxTimes : 0;
    
    return @{
        @"host": self.request.domain ?: @"",
        @"method": @"ping",
        @"trace_id": CLSIdGenerator.generateTraceId,
        @"appKey": self.request.appKey ?: @"",
        @"host_ip": [self resolveHostToIP:self.request.domain] ?: @"",
        @"interface": self.interfaceInfo[@"type"] ?: @"unknown",
        @"count": @(self.request.maxTimes),
        @"size": @(self.request.size),
        @"total": @([[self.latencies valueForKeyPath:@"@sum.self"] doubleValue]),
        @"loss": @(lossRate),
        @"latency_min": minLatency,
        @"latency_max": maxLatency,
        @"latency": avgLatency,
        @"stddev": stddev,
        @"responseNum": @(_successCount),
        @"exceptionNum": @(_failureCount),
        @"bindFailed": @(_bindFailedCount),
        @"src": @"app"
    };
}

- (NSDictionary *)buildEnhancedNetworkInfo {
//    NSMutableDictionary *networkInfo = [[CLSNetworkUtils getNetworkEnvironmentInfo:self.interfaceInfo[@"type"]] mutableCopy];
//    return [networkInfo copy];
    return nil;
}

- (NSNumber *)calculateStdDev {
    if (_latencies.count == 0) return @0;
    
    double mean = [[_latencies valueForKeyPath:@"@avg.self"] doubleValue];
    double sumOfSquaredDifferences = 0.0;
    
    for (NSNumber *latency in _latencies) {
        double difference = [latency doubleValue] - mean;
        sumOfSquaredDifferences += difference * difference;
    }
    
    double variance = sumOfSquaredDifferences / _latencies.count;
    return @(sqrt(variance));
}

- (void)cancelTimeoutTimer {
    if (_timeoutTimer) {
        dispatch_source_cancel(_timeoutTimer);
        _timeoutTimer = nil;
    }
}

- (void)completePingWithError:(NSError *)error {
    if (_isCompleted) return;
    _isCompleted = YES;
    
    [self cancelTimeoutTimer];
    
    CLSMultiInterfacePingResult *result = [self buildPingResult];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionHandler) {
            self.completionHandler(result, error);
            self.completionHandler = nil;
        }
    });
}

- (void)handleTimeout {
    _isCompleted = YES;
    [self cancelTimeoutTimer];
    
    NSError *error = [NSError errorWithDomain:@"CLSTcpingErrorDomain"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Request timeout"}];
    [self completePingWithError:error];
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

- (void)startPingWithCompletion:(NSDictionary *)currentInterface
                     completion:(void (^)(CLSMultiInterfacePingResult *result, NSError *error))completion {
    self.completionHandler = completion;
    self.isCompleted = NO;
    self.interfaceInfo = [currentInterface copy];
    
    // 重置状态
    self.successCount = 0;
    self.failureCount = 0;
    self.bindFailedCount = 0;
    [_latencies removeAllObjects];
    
    // 设置超时控制
    [self setupTimeoutTimer];
    
    // 启动异步Ping测试
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (NSUInteger i = 0; i < self.request.maxTimes && !self->_isCompleted; i++) {
            [self performPing];
        }
        
        if (!self->_isCompleted) {
            [self completePingWithError:nil];
        }
    });
}

- (NSDictionary *)buildReportDataFromPingResult:(CLSMultiInterfacePingResult *)result {
    NSMutableDictionary *reportData = [NSMutableDictionary dictionaryWithDictionary:result.netOrigin];
    
    // 添加网络信息
    reportData[@"netInfo"] = result.netInfo ?: @{};
    reportData[@"detectEx"] = result.detectEx ?: @{};
    reportData[@"userEx"] = result.userEx ?: @{};
    
    // 添加时间戳
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970] * 1000;
    reportData[@"timestamp"] = @(timestamp);
    reportData[@"startDate"] = @(timestamp);
    
    return [reportData copy];
}

- (void)start:(CLSPingRequest *) request complate:(CompleteCallback)complate {
    
    NSArray<NSDictionary *> *availableInterfaces = [CLSNetworkUtils getAvailableInterfacesForType];
    
    for (NSDictionary *currentInterface in availableInterfaces) {
        NSLog(@"interface:%@",currentInterface);
        CLSSpanBuilder *builder = [[CLSSpanBuilder builder] initWithName:@"network_diagnosis" provider:[[CLSSpanProviderDelegate alloc] init]];
        [builder setURL:request.domain];
        CLSMultiInterfacePing *ping = [[CLSMultiInterfacePing alloc] initWithRequest:request];
        [self startPingWithCompletion:currentInterface completion:^(CLSMultiInterfacePingResult *result, NSError *error) {
            NSDictionary *reportData = [self buildReportDataFromPingResult:result];
            CLSResponse *complateResult = [CLSResponse complateResultWithContent:reportData];
            if (complate) {
                complate(complateResult);
            }
            [builder report:self.topicId reportData:reportData];
        }];
    }

}

@end

