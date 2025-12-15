//
//  CLSDnsping.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/20.
//

#import <Foundation/Foundation.h>
#import "CLSDnsping.h"
#import "CLSNetworkUtils.h"
#import <netinet/in.h>
#import <sys/types.h>
#import <netinet/in.h>
#import <arpa/nameser.h> // 定义 NS_PACKETSZ
#import <resolv.h>
#import <netdb.h>
#import <arpa/inet.h>
#import <sys/ioctl.h>
#import <net/if.h>
#import <sys/socket.h>
#import "CLSIdGenerator.h"
#import "CLSResponse.h"
#import "CLSIdGenerator.h"
#import "CLSNetworkUtils.h"
#import "CLSSPanBuilder.h"
#import "CLSCocoa.h"
#import "CLSStringUtils.h"

@implementation CLSDnsResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _netType = @"dns";
        _eventType = @"net_d";
        _success = NO;
        _flags = @"";
        _querySection = @[];
        _answerSection = @[];
        _authoritySection = @[];
        _additionalSection = @[];
        _questionCount = 0;
        _answerCount = 0;
        _authorityCount = 0;
        _additionalCount = 0;
    }
    return self;
}

@end

@implementation CLSMultiInterfaceDns {
    NSMutableArray<NSNumber *> *_latencies;
    NSUInteger _successCount;
    NSUInteger _failureCount;
    NSString *_currentInterface;
    NSMutableArray<NSString *> *_resolvedIPs;
    dispatch_source_t _timeoutTimer;
    BOOL _isCompleted;
}


- (instancetype)initWithRequest:(CLSDnsRequest *)request {
    self = [super init];
    if (self) {
        _request = request;
        _latencies = [NSMutableArray array];
        _resolvedIPs = [NSMutableArray array];
        _currentInterface = @"unknown";
        _isCompleted = NO;
    }
    return self;
}

- (int)performDnsQuery:(const char *)host
                server:(const char *)dnsServer
               latency:(NSTimeInterval *)latency
           resolvedIPs:(NSMutableArray<NSString *> *)resolvedIPs
                 flags:(NSString * __autoreleasing *)flags
        questionSection:(NSMutableArray * __autoreleasing *)questionSection
         answerSection:(NSMutableArray * __autoreleasing *)answerSection
      authoritySection:(NSMutableArray * __autoreleasing *)authoritySection
     additionalSection:(NSMutableArray * __autoreleasing *)additionalSection
          questionCount:(int *)questionCount
           answerCount:(int *)answerCount
       authorityCount:(int *)authorityCount
      additionalCount:(int *)additionalCount {
    
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    
    // 创建socket
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        *latency = 0;
        return -1;
    }
    
    // 绑定到指定接口
    if (_currentInterface && ![_currentInterface isEqualToString:@"unknown"]) {
        NSString *sourceIP = [CLSNetworkUtils getIPAddressForInterface:_currentInterface];
        if (sourceIP) {
            struct sockaddr_in localAddr;
            memset(&localAddr, 0, sizeof(localAddr));
            localAddr.sin_family = AF_INET;
            localAddr.sin_port = 0;
            inet_pton(AF_INET, sourceIP.UTF8String, &localAddr.sin_addr);
            
            if (bind(sock, (struct sockaddr *)&localAddr, sizeof(localAddr)) == -1) {
                close(sock);
                return -1;
            }
        }
    }
    
    // DNS查询
    struct __res_state res;
    memset(&res, 0, sizeof(res));
    
    int result = res_ninit(&res);
    if (result == 0) {
        // 配置DNS服务器
        if (dnsServer != NULL && strcmp(dnsServer, "system") != 0) {
            struct in_addr addr;
            if (inet_pton(AF_INET, dnsServer, &addr) == 1) {
                res.nsaddr_list[0].sin_addr = addr;
                res.nsaddr_list[0].sin_family = AF_INET;
                res.nsaddr_list[0].sin_port = htons(53);
                res.nscount = 1;
            }
        }
        
        res.retrans = (int)self.request.timeout;
        res.retry = 1;
        
        unsigned char answer[NS_PACKETSZ];
        int len = res_nsearch(&res, host, ns_c_in, ns_t_a, answer, sizeof(answer));
        
        CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
        *latency = (endTime - startTime) * 1000;
        
        if (len > 0) {
            // 解析DNS响应报文头部和各个部分[1,6](@ref)
            [self parseDnsResponse:answer
                             length:len
                              flags:flags
                    questionSection:questionSection
                     answerSection:answerSection
                  authoritySection:authoritySection
                 additionalSection:additionalSection
                     questionCount:questionCount
                      answerCount:answerCount
                  authorityCount:authorityCount
                 additionalCount:additionalCount];
            
            // 解析回答部分获取IP地址
            ns_msg handle;
            if (ns_initparse(answer, len, &handle) == 0) {
                int count = ns_msg_count(handle, ns_s_an);
                for (int i = 0; i < count; i++) {
                    ns_rr rr;
                    if (ns_parserr(&handle, ns_s_an, i, &rr) == 0) {
                        if (ns_rr_type(rr) == ns_t_a) {
                            char ip[INET_ADDRSTRLEN];
                            inet_ntop(AF_INET, ns_rr_rdata(rr), ip, sizeof(ip));
                            NSString *ipString = [NSString stringWithUTF8String:ip];
                            if (![resolvedIPs containsObject:ipString]) {
                                [resolvedIPs addObject:ipString];
                            }
                        }
                    }
                }
            }
        }
        
        res_ndestroy(&res);
        close(sock);
        return len;
    }
    
    close(sock);
    *latency = 0;
    return result;
}

- (void)performDnsResolution {
    if (!self.request.domain) {
        _failureCount++;
        return;
    }
    
    const char *host = [self.request.domain UTF8String];
    const char *dnsServer = [self.request.nameServer UTF8String];
    
    NSTimeInterval latency = 0;
    NSMutableArray<NSString *> *resolvedIPs = [NSMutableArray array];
    
    // 使用局部变量接收解析结果
    NSString *flags = nil;
    NSMutableArray *questionSection = nil;
    NSMutableArray *answerSection = nil;
    NSMutableArray *authoritySection = nil;
    NSMutableArray *additionalSection = nil;
    int questionCount = 0, answerCount = 0, authorityCount = 0, additionalCount = 0;
    
    int result = [self performDnsQuery:host
                                server:dnsServer
                               latency:&latency
                           resolvedIPs:resolvedIPs
                                 flags:&flags
                        questionSection:&questionSection
                         answerSection:&answerSection
                      authoritySection:&authoritySection
                     additionalSection:&additionalSection
                         questionCount:&questionCount
                          answerCount:&answerCount
                      authorityCount:&authorityCount
                     additionalCount:&additionalCount];
    
    if (result > 0 && resolvedIPs.count > 0) {
        [_latencies addObject:@(latency)];
        [_resolvedIPs addObjectsFromArray:resolvedIPs];
        _successCount++;
        
        // 将结果存入CLSDnsResult对象（示例逻辑）
        if (self.completionHandler) {
            CLSDnsResult *resultObj = [[CLSDnsResult alloc] init];
            resultObj.flags = flags;
            resultObj.querySection = questionSection;
            resultObj.answerSection = answerSection;
            resultObj.authoritySection = authoritySection;
            resultObj.additionalSection = additionalSection;
            resultObj.questionCount = questionCount;
            resultObj.answerCount = answerCount;
            resultObj.authorityCount = authorityCount;
            resultObj.additionalCount = additionalCount;
            
            self.completionHandler(resultObj, nil);
        }
        
        NSLog(@"✅ DNS解析成功: %@ -> %@, 延迟: %.3fms",
              self.request.domain, [resolvedIPs componentsJoinedByString:@", "], latency);
    } else {
        _failureCount++;
        NSLog(@"❌ DNS解析失败: %@, 错误码: %d", self.request.domain, result);
    }
}

- (void)startDnsWithCompletion:(NSString *)currentInterface
                    completion:(void (^)(CLSDnsResult *result, NSError *error))completion {
    self.completionHandler = completion;
    _isCompleted = NO;
    _currentInterface = currentInterface;
    
    // 重置状态
    _successCount = 0;
    _failureCount = 0;
    [_latencies removeAllObjects];
    [_resolvedIPs removeAllObjects];
    
    // 设置超时控制
    [self setupTimeoutTimer];
    
    // 启动异步DNS测试
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (NSUInteger i = 0; i < self.request.maxTimes && !self->_isCompleted; i++) {
            [self performDnsResolution];
        }
        
        if (!self->_isCompleted) {
            [self completeDnsWithError:nil];
        }
    });
}

- (void)setupTimeoutTimer {
    if (_timeoutTimer) {
        dispatch_source_cancel(_timeoutTimer);
    }
    
    _timeoutTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    
    dispatch_source_set_timer(_timeoutTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.request.timeout * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER, 0);
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_timeoutTimer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf handleTimeout];
        }
    });
    
    dispatch_resume(_timeoutTimer);
}

- (void)handleTimeout {
    _isCompleted = YES;
    [self cancelTimeoutTimer];
    
    NSError *error = [NSError errorWithDomain:@"CLSDnsErrorDomain"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"DNS resolution timeout"}];
    [self completeDnsWithError:error];
}

- (void)cancelTimeoutTimer {
    if (_timeoutTimer) {
        dispatch_source_cancel(_timeoutTimer);
        _timeoutTimer = nil;
    }
}

- (void)completeDnsWithError:(NSError *)error {
    if (_isCompleted) return;
    _isCompleted = YES;
    
    [self cancelTimeoutTimer];
    
    CLSDnsResult *result = [self buildDnsResult];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionHandler) {
            self.completionHandler(result, error);
            self.completionHandler = nil;
        }
    });
}

- (CLSDnsResult *)buildDnsResult {
    CLSDnsResult *result = [[CLSDnsResult alloc] init];
    result.netType = @"dns";
    result.eventType = @"net_d";
    result.success = (_failureCount == 0);
    result.totalTime = [[_latencies valueForKeyPath:@"@sum.self"] doubleValue];
    
    // 构建netOrigin
    result.netOrigin = [self buildNetOriginWithResult:result];
    
    // 构建netInfo
    result.netInfo = [self buildEnhancedNetworkInfo];
    
    result.detectEx = self.request.detectEx ?: @{};
    result.userEx = self.request.userEx ?: @{};
    
    return result;
}

- (void)parseDnsResponse:(unsigned char *)response
                 length:(int)length
                  flags:(NSString * __autoreleasing *)flags
        questionSection:(NSMutableArray<NSDictionary *> * __autoreleasing *)questionSection
         answerSection:(NSMutableArray<NSDictionary *> * __autoreleasing *)answerSection
      authoritySection:(NSMutableArray<NSDictionary *> * __autoreleasing *)authoritySection
     additionalSection:(NSMutableArray<NSDictionary *> * __autoreleasing *)additionalSection
         questionCount:(int *)questionCount
          answerCount:(int *)answerCount
      authorityCount:(int *)authorityCount
     additionalCount:(int *)additionalCount;{
    
    ns_msg handle;
    if (ns_initparse(response, length, &handle) != 0) {
        return;
    }
    
    // 解析标志字段[6,8](@ref)
    uint16_t flagsValue = ns_msg_getflag(handle, ns_f_opcode);
    *flags = [NSString stringWithFormat:@"%04x", flagsValue];
    
    // 获取各部分数量[6](@ref)
    *questionCount = ns_msg_count(handle, ns_s_qd);
    *answerCount = ns_msg_count(handle, ns_s_an);
    *authorityCount = ns_msg_count(handle, ns_s_ns);
    *additionalCount = ns_msg_count(handle, ns_s_ar);
    
    // 解析问题区域
    NSMutableArray *questions = [NSMutableArray array];
    for (int i = 0; i < *questionCount; i++) {
        ns_rr rr;
        if (ns_parserr(&handle, ns_s_qd, i, &rr) == 0) {
            char name[NS_MAXDNAME];
            ns_name_uncompress(response, response + length, ns_rr_name(rr), name, NS_MAXDNAME);
            
            NSString *qname = [NSString stringWithUTF8String:name];
            NSString *qtype = [self typeToString:ns_rr_type(rr)];
            
            [questions addObject:@{
                @"name": qname ?: @"",
                @"type": qtype ?: @""
            }];
        }
    }
    *questionSection = questions;
    
    // 解析回答区域[1](@ref)
    NSMutableArray *answers = [NSMutableArray array];
    for (int i = 0; i < *answerCount; i++) {
        ns_rr rr;
        if (ns_parserr(&handle, ns_s_an, i, &rr) == 0) {
            [answers addObject:[self parseResourceRecord:response length:length rr:rr]];
        }
    }
    *answerSection = answers;
    
    // 解析权威区域
    NSMutableArray *authorities = [NSMutableArray array];
    for (int i = 0; i < *authorityCount; i++) {
        ns_rr rr;
        if (ns_parserr(&handle, ns_s_ns, i, &rr) == 0) {
            [authorities addObject:[self parseResourceRecord:response length:length rr:rr]];
        }
    }
    *authoritySection = authorities;
    
    // 解析附加区域
    NSMutableArray *additionals = [NSMutableArray array];
    for (int i = 0; i < *additionalCount; i++) {
        ns_rr rr;
        if (ns_parserr(&handle, ns_s_ar, i, &rr) == 0) {
            [additionals addObject:[self parseResourceRecord:response length:length rr:rr]];
        }
    }
    *additionalSection = additionals;
}

- (NSDictionary *)parseResourceRecord:(unsigned char *)response
                               length:(int)length
                                    rr:(ns_rr)rr {
    char name[NS_MAXDNAME];
    ns_name_uncompress(response, response + length, ns_rr_name(rr), name, NS_MAXDNAME);
    
    NSString *rrName = [NSString stringWithUTF8String:name];
    NSString *rrType = [self typeToString:ns_rr_type(rr)];
    uint32_t ttl = ns_rr_ttl(rr);
    
    NSMutableDictionary *record = [NSMutableDictionary dictionaryWithDictionary:@{
        @"name": rrName ?: @"",
        @"ttl": @(ttl),
        @"atype": rrType ?: @"",
        @"value": @""
    }];
    
    // 根据记录类型解析值[7](@ref)
    switch (ns_rr_type(rr)) {
        case ns_t_a: {
            // A记录：IPv4地址
            if (ns_rr_rdlen(rr) == 4) {
                const unsigned char *data = ns_rr_rdata(rr);
                char ip[INET_ADDRSTRLEN];
                snprintf(ip, sizeof(ip), "%d.%d.%d.%d", data[0], data[1], data[2], data[3]);
                record[@"value"] = [NSString stringWithUTF8String:ip];
            }
            break;
        }
        case ns_t_aaaa: {
            // AAAA记录：IPv6地址
            if (ns_rr_rdlen(rr) == 16) {
                char ip[INET6_ADDRSTRLEN];
                const unsigned char *data = ns_rr_rdata(rr);
                inet_ntop(AF_INET6, data, ip, sizeof(ip));
                record[@"value"] = [NSString stringWithUTF8String:ip];
            }
            break;
        }
        case ns_t_cname: {
            // CNAME记录：规范名称
            char cname[NS_MAXDNAME];
            ns_name_uncompress(response, response + length,
                             ns_rr_rdata(rr), cname, sizeof(cname));
            record[@"value"] = [NSString stringWithUTF8String:cname];
            break;
        }
        default:
            record[@"value"] = @"";
            break;
    }
    
    return [record copy];
}

- (NSString *)typeToString:(ns_type)type {
    switch (type) {
        case ns_t_a: return @"A";
        case ns_t_aaaa: return @"AAAA";
        case ns_t_cname: return @"CNAME";
        case ns_t_mx: return @"MX";
        case ns_t_ns: return @"NS";
        case ns_t_soa: return @"SOA";
        case ns_t_ptr: return @"PTR";
        case ns_t_txt: return @"TXT";
        default: return [NSString stringWithFormat:@"%d", type];
    }
}

- (NSDictionary *)buildNetOriginWithResult:(CLSDnsResult *)result {
    NSNumber *minLatency = [_latencies valueForKeyPath:@"@min.self"] ?: @0;
    NSNumber *maxLatency = [_latencies valueForKeyPath:@"@max.self"] ?: @0;
    NSNumber *avgLatency = [_latencies valueForKeyPath:@"@avg.self"] ?: @0;
    
    double lossRate = self.request.maxTimes > 0 ? (double)_failureCount / self.request.maxTimes : 0;
    NSString *resolvedIPsString = [_resolvedIPs componentsJoinedByString:@","];
    
    return @{
        @"method": @"dns",
        @"trace_id": CLSIdGenerator.generateTraceId,
        @"domain": self.request.domain ?: @"",
        @"status": _failureCount == 0 ? @"success" : @"fail",
        @"id": CLSIdGenerator.generateTraceId,
        @"flags": result.flags ?: @"",
        @"latency": avgLatency,
        @"host_ip": resolvedIPsString ?: @"",
        @"QUESTION-SECTION": result.querySection ?: @[],
        @"ANSWER-SECTION": result.answerSection ?: @[],
        @"QUERY": @(result.questionCount),
        @"ANSWER": @(result.answerCount),
        @"AUTHORITY": @(result.authorityCount),
        @"ADDITIONAL": @(result.additionalCount),
        @"appKey": self.request.appKey ?: @"",
        @"src": @"app",
        // 其他原有字段...
    };
}

- (NSDictionary *)buildEnhancedNetworkInfo {
//    NSMutableDictionary *networkInfo = [[CLSNetworkUtils getNetworkEnvironmentInfo:_currentInterface ] mutableCopy];
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

- (NSDictionary *)buildReportDataFromDnsResult:(CLSDnsResult *)result {
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

- (void)start:(CLSDnsRequest *) request complate:(CompleteCallback)complate{
    NSArray<NSString *> *availableInterfaces = [CLSNetworkUtils getAvailableInterfacesForType];
    for (NSString *currentInterface in availableInterfaces) {
        NSLog(@"interface:%@",currentInterface);
        CLSSpanBuilder *builder = [[CLSSpanBuilder builder] initWithName:@"network_diagnosis" provider:[[CLSSpanProviderDelegate alloc] init]];
        [builder setURL:request.domain];
        [self startDnsWithCompletion:currentInterface completion:^(CLSDnsResult *result, NSError *error) {
            NSDictionary *reportData = [self buildReportDataFromDnsResult:result];
            CLSResponse *complateResult = [CLSResponse complateResultWithContent:reportData];
            if (complate) {
                complate(complateResult);
            }
            [builder report:self.topicId reportData:reportData];
        }];
    }
}

@end
