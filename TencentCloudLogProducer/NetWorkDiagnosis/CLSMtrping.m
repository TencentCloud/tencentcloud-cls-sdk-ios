#import "CLSMtrping.h"
#import "CLSNetworkUtils.h"
#import <netinet/in.h>
#import <netinet/ip.h>
#import <netinet/ip_icmp.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <netdb.h>
#import "CLSIdGenerator.h"
#import "CLSSPanBuilder.h"
#import "CLSCocoa.h"

#define PACKET_SIZE 64
#define MAX_HOPS 30
#define TIMEOUT 3
#define ATTEMPTS 3

@implementation CLSMtrResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _netType = @"mtr";
        _eventType = @"net_d";
        _success = NO;
        _paths = @[];
        _netOrigin = @{};
        _netInfo = @{};
    }
    return self;
}

@end

@implementation CLSMultiInterfaceMtr {
    dispatch_source_t _timeoutTimer;
}

- (instancetype)initWithRequest:(CLSMtrRequest *)request {
    self = [super init];
    if (self) {
        _request = request;
        _pathsResults = [NSMutableArray array];
        _currentInterface = @"unknown";
        _isCompleted = NO;
        _sockfd = -1;
        _bindFailedCount = 0;
    }
    return self;
}

#pragma mark - 多网卡绑定支持
- (int)bindSocketToInterface:(NSString *)interfaceName {
    if (!interfaceName || [interfaceName isEqualToString:@"unknown"]) {
        return 0;
    }
    
    NSString *sourceIP = [CLSNetworkUtils getIPAddressForInterface:interfaceName];
    if (!sourceIP) {
        NSLog(@"🟡 Could not get IP for interface: %@", interfaceName);
        return -1;
    }
    
    struct sockaddr_in localAddr;
    memset(&localAddr, 0, sizeof(localAddr));
    localAddr.sin_family = AF_INET;
    localAddr.sin_port = 0;
    inet_pton(AF_INET, sourceIP.UTF8String, &localAddr.sin_addr);
    
    if (bind(_sockfd, (struct sockaddr *)&localAddr, sizeof(localAddr)) == -1) {
        NSLog(@"❌ Bind to interface %@ (IP: %@) failed: %s",
              interfaceName, sourceIP, strerror(errno));
        _bindFailedCount++;
        return -1;
    }
    
    NSLog(@"✅ Successfully bound to interface: %@ (IP: %@)", interfaceName, sourceIP);
    return 0;
}

#pragma mark - 超时控制
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
    
    NSError *error = [NSError errorWithDomain:@"CLSMtrErrorDomain"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"MTR probe timeout"}];
    [self completeWithError:error];
}

- (void)cancelTimeoutTimer {
    if (_timeoutTimer) {
        dispatch_source_cancel(_timeoutTimer);
        _timeoutTimer = nil;
    }
}

#pragma mark - MTR探测核心逻辑
- (void)startMtrWithCompletion:(NSDictionary *)currentInterface
                    completion:(void (^)(CLSMtrResult *result, NSError *error))completion {
    self.completionHandler = completion;
    self.isCompleted = NO;
    
    // 获取接口信息
    self.interfaceInfo = [currentInterface copy];
    
    NSLog(@"🔍 Starting MTR probe on interface: %@", self.currentInterface);
    
    // 设置超时控制
    [self setupTimeoutTimer];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self executeMtrProbe];
    });
}

- (void)executeMtrProbe {
    NSString *host = self.request.domain;
    if (!host) {
        [self completeWithError:[NSError errorWithDomain:@"CLSMtrErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid host"}]];
        return;
    }
    
    // 创建socket
    _sockfd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    if (_sockfd < 0) {
        [self completeWithError:[NSError errorWithDomain:@"CLSMtrErrorDomain" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create socket"}]];
        return;
    }
    
    // 绑定到指定网卡
    if ([self bindSocketToInterface:self.currentInterface] != 0) {
        close(_sockfd);
        [self completeWithError:[NSError errorWithDomain:@"CLSMtrErrorDomain" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to bind to interface"}]];
        return;
    }
    
    // 设置超时
    struct timeval tv;
    tv.tv_sec = TIMEOUT;
    tv.tv_usec = 0;
    setsockopt(_sockfd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    
    // 解析目标主机
    struct sockaddr_in destAddr;
    if (![self resolveHost:host toAddress:&destAddr]) {
        close(_sockfd);
        [self completeWithError:[NSError errorWithDomain:@"CLSMtrErrorDomain" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"DNS resolution failed"}]];
        return;
    }
    
    NSString *hostIP = [NSString stringWithUTF8String:inet_ntoa(destAddr.sin_addr)];
    NSLog(@"🎯 MTR target: %@ -> %@", host, hostIP);
    
    // 执行路径探测
    for (int ttl = 1; ttl <= self.request.maxHops && !_isCompleted; ttl++) {
        NSDictionary *hopResult = [self probeHop:ttl destination:&destAddr];
        if (hopResult) {
            [self.pathsResults addObject:hopResult];
            
            // 如果到达目标，停止探测
            if ([hopResult[@"ip"] isEqualToString:hostIP]) {
                break;
            }
        }
        
        // 短暂延迟
        [NSThread sleepForTimeInterval:0.1];
    }
    
    close(_sockfd);
    
    if (!_isCompleted) {
        [self completeWithSuccess];
    }
}

- (NSDictionary *)probeHop:(int)ttl destination:(struct sockaddr_in *)destAddr {
    // 设置TTL
    if (setsockopt(_sockfd, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) < 0) {
        NSLog(@"❌ Failed to set TTL: %d", ttl);
        return nil;
    }
    
    // 准备ICMP包
    struct icmp packet;
    memset(&packet, 0, sizeof(packet));
    packet.icmp_type = ICMP_ECHO;
    packet.icmp_code = 0;
    packet.icmp_cksum = 0;
    packet.icmp_id = getpid() & 0xFFFF;
    packet.icmp_seq = ttl;
    
    // 计算校验和
    packet.icmp_cksum = [self checksum:(unsigned short *)&packet length:sizeof(packet)];
    
    // 记录发送时间
    struct timeval sendTime;
    gettimeofday(&sendTime, NULL);
    
    // 发送探测包
    ssize_t sent = sendto(_sockfd, &packet, sizeof(packet), 0,
                         (struct sockaddr *)destAddr, sizeof(*destAddr));
    if (sent <= 0) {
        NSLog(@"❌ Failed to send packet for TTL: %d", ttl);
        return @{
            @"hop": @(ttl),
            @"ip": @"*",
            @"latency": @(-1),
            @"loss": @(1.0),
            @"interface": self.currentInterface ?: @"unknown"
        };
    }
    
    // 接收响应
    char recvBuffer[1500];
    struct sockaddr_in fromAddr;
    socklen_t fromAddrLen = sizeof(fromAddr);
    
    fd_set readfds;
    struct timeval timeout;
    timeout.tv_sec = TIMEOUT;
    timeout.tv_usec = 0;
    
    FD_ZERO(&readfds);
    FD_SET(_sockfd, &readfds);
    
    int selectResult = select(_sockfd + 1, &readfds, NULL, NULL, &timeout);
    
    if (selectResult > 0 && FD_ISSET(_sockfd, &readfds)) {
        ssize_t received = recvfrom(_sockfd, recvBuffer, sizeof(recvBuffer), 0,
                                  (struct sockaddr *)&fromAddr, &fromAddrLen);
        
        // 计算延迟
        struct timeval recvTime;
        gettimeofday(&recvTime, NULL);
        NSTimeInterval latency = [self calculateLatency:sendTime endTime:recvTime];
        
        if (received > 0) {
            return @{
                @"hop": @(ttl),
                @"ip": [NSString stringWithUTF8String:inet_ntoa(fromAddr.sin_addr)],
                @"latency": @(latency),
                @"loss": @(0.0),
                @"interface": self.currentInterface ?: @"unknown"
            };
        }
    }
    
    NSLog(@"🟡 No response for TTL: %d", ttl);
    return @{
        @"hop": @(ttl),
        @"ip": @"*",
        @"latency": @(-1),
        @"loss": @(1.0),
        @"interface": self.currentInterface ?: @"unknown"
    };
}

#pragma mark - 结果处理
- (void)completeWithSuccess {
    CLSMtrResult *result = [self buildMtrResult];
    [self completeWithError:nil result:result];
}

- (void)completeWithError:(NSError *)error {
    [self completeWithError:error result:[self buildMtrResult]];
}

- (void)completeWithError:(NSError *)error result:(CLSMtrResult *)result {
    self.isCompleted = YES;
    [self cancelTimeoutTimer];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionHandler) {
            self.completionHandler(result, error);
            self.completionHandler = nil;
        }
    });
}

- (CLSMtrResult *)buildMtrResult {
    CLSMtrResult *result = [[CLSMtrResult alloc] init];
    
    result.success = (self.pathsResults.count > 0);
    result.totalTime = [self calculateTotalTime];
    result.netOrigin = [self buildNetOrigin];
    result.paths = [self buildPaths];
    result.netInfo = [self buildEnhancedNetworkInfo];
    result.detectEx = self.request.detectEx ?: @{};
    result.userEx = self.request.userEx ?: @{};
    
    return result;
}

- (NSDictionary *)buildNetOrigin {
    NSString *hostIP = [self resolveHostToIP:self.request.domain] ?: @"unknown";
    
    return @{
        @"method": @"mtr",
        @"trace_id": CLSIdGenerator.generateTraceId,
        @"appKey": self.request.appKey ?: @"",
        @"host": self.request.domain ?: @"",
        @"type": @"all",
        @"max_paths": @(self.request.maxHops),
        @"src": @"app",
        @"host_ip": hostIP,
        @"interface": self.currentInterface ?: @"unknown",
        @"timestamp": @([NSDate date].timeIntervalSince1970 * 1000)
    };
}

- (NSArray *)buildPaths {
    if (self.pathsResults.count == 0) {
        return @[];
    }
    
    NSString *hostIP = [self resolveHostToIP:self.request.domain] ?: @"";
    NSMutableArray *hopResults = [NSMutableArray array];
    
    for (NSDictionary *hopData in self.pathsResults) {
        NSDictionary *resultDict = @{
            @"loss": hopData[@"loss"] ?: @0,
            @"latency_min": hopData[@"latency"] ?: @0,
            @"latency_max": hopData[@"latency"] ?: @0,
            @"latency": hopData[@"latency"] ?: @0,
            @"responseNum": @1,
            @"ip": hopData[@"ip"] ?: @"",
            @"hop": hopData[@"hop"] ?: @0,
            @"stddev": @0
        };
        
        NSDictionary *pathData = @{
            @"method": @"mtr",
            @"trace_id": CLSIdGenerator.generateTraceId,
            @"host": self.request.domain ?: @"",
            @"host_ip": hostIP,
            @"type": @"path",
            @"path": [NSString stringWithFormat:@"%@:%@-%@",
                     @((NSInteger)([NSDate date].timeIntervalSince1970 * 1000)),
                     self.currentInterface ?: @"unknown",
                     hostIP],
            @"lastHop": @(self.pathsResults.count),
            @"timestamp": @((NSInteger)([NSDate date].timeIntervalSince1970 * 1000)),
            @"interface": self.currentInterface ?: @"unknown",
            @"protocol": @"ICMP",
            @"exceptionNum": @(-8),
            @"bindFailed": @(self.bindFailedCount),
            @"result": @[resultDict]
        };
        
        [hopResults addObject:pathData];
    }
    
    return hopResults;
}

- (NSDictionary *)buildEnhancedNetworkInfo {
//    NSMutableDictionary *networkInfo = [[CLSNetworkUtils getNetworkEnvironmentInfo:self.interfaceInfo[@"type"]] mutableCopy];
//    return [networkInfo copy];
    return nil;
}

#pragma mark - 工具方法
- (BOOL)resolveHost:(NSString *)host toAddress:(struct sockaddr_in *)addr {
    memset(addr, 0, sizeof(struct sockaddr_in));
    addr->sin_family = AF_INET;
    addr->sin_port = 0;
    
    const char *hostCString = [host UTF8String];
    addr->sin_addr.s_addr = inet_addr(hostCString);
    
    if (addr->sin_addr.s_addr == INADDR_NONE) {
        struct hostent *hostEntry = gethostbyname(hostCString);
        if (hostEntry == NULL || hostEntry->h_addr == NULL) {
            return NO;
        }
        addr->sin_addr = *(struct in_addr *)hostEntry->h_addr;
    }
    
    return YES;
}

- (NSString *)resolveHostToIP:(NSString *)host {
    struct hostent *hostentry = gethostbyname([host UTF8String]);
    if (hostentry && hostentry->h_addr_list[0]) {
        struct in_addr ip_addr;
        memcpy(&ip_addr, hostentry->h_addr_list[0], sizeof(ip_addr));
        return [NSString stringWithUTF8String:inet_ntoa(ip_addr)];
    }
    return nil;
}

- (unsigned short)checksum:(unsigned short *)buffer length:(size_t)length {
    unsigned int sum = 0;
    unsigned short result;
    
    while (length > 1) {
        sum += *buffer++;
        length -= 2;
    }
    
    if (length == 1) {
        sum += *(unsigned char *)buffer;
    }
    
    sum = (sum >> 16) + (sum & 0xFFFF);
    sum += (sum >> 16);
    result = ~sum;
    
    return result;
}

- (NSTimeInterval)calculateLatency:(struct timeval)startTime endTime:(struct timeval)endTime {
    NSTimeInterval start = startTime.tv_sec + startTime.tv_usec / 1000000.0;
    NSTimeInterval end = endTime.tv_sec + endTime.tv_usec / 1000000.0;
    return (end - start) * 1000;
}

- (NSTimeInterval)calculateTotalTime {
    NSTimeInterval total = 0;
    for (NSDictionary *hop in self.pathsResults) {
        NSNumber *latency = hop[@"latency"];
        if (latency.doubleValue > 0) {
            total += latency.doubleValue;
        }
    }
    return total;
}

#pragma mark - 公共接口
- (NSDictionary *)buildReportDataFromMtrResult:(CLSMtrResult *)mtrResult {
    // 1. 基础结构构建
    NSMutableDictionary *reportData = [NSMutableDictionary dictionary];
    
    // 2. 填充顶层字段（method/trace_id等）
    [reportData addEntriesFromDictionary:@{
        @"method": @"mtr",
        @"trace_id": mtrResult.netOrigin[@"trace_id"] ?: @"",
        @"appKey": mtrResult.netOrigin[@"appKey"] ?: @"",
        @"host": mtrResult.netOrigin[@"host"] ?: @"",
        @"type": @"all",
        @"max_paths": mtrResult.netOrigin[@"max_paths"] ?: @30,
        @"src": @"app"
    }];
    
    // 3. 构建paths数组
    reportData[@"paths"] = mtrResult.paths ?: @[];
    
    // 4. 构建netInfo（网络环境信息）
    reportData[@"netInfo"] = mtrResult.netInfo ?: @{};
    
    // 5. 处理扩展字段
    reportData[@"detectEx"] = mtrResult.detectEx ?: @{};
    reportData[@"userEx"] = mtrResult.userEx ?: @{};
    
    return [reportData copy];
}

- (void)start:(CLSMtrRequest *) request complate:(CompleteCallback)complate{
    NSArray<NSDictionary *> *availableInterfaces = [CLSNetworkUtils getAvailableInterfacesForType];
    for (NSDictionary *currentInterface in availableInterfaces) {
        NSLog(@"interface:%@", currentInterface);
        CLSSpanBuilder *builder = [[CLSSpanBuilder builder] initWithName:@"network_diagnosis" provider:[[CLSSpanProviderDelegate alloc] init]];
        [builder setURL:request.domain];
        [self startMtrWithCompletion:currentInterface completion:^(CLSMtrResult *result, NSError *error) {
            NSDictionary *reportData = [self buildReportDataFromMtrResult:result];
            CLSResponse *complateResult = [CLSResponse complateResultWithContent:reportData];
            if (complate) {
                complate(complateResult);
            }
            [builder report:self.topicId reportData:reportData];
        }];
    }
}

@end
