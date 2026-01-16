#import "CLSHttpingV2.h"
#import "CLSNetworkUtils.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CLSResponse.h"
#import "CLSIdGenerator.h"
#import "CLSSPanBuilder.h"
#import "CLSCocoa.h"
#import "CLSStringUtils.h"

@implementation CLSMultiInterfaceHttping

- (instancetype)initWithRequest:(CLSHttpRequest *)request {
    self = [super init];
    if (self) {
        _request = request;
        _timingMetrics = [NSMutableDictionary dictionary];
        _responseData = [NSMutableData data];
        _interfaceInfo = @{};
    }
    return self;
}

- (void)dealloc {
    if (_timeoutTimer) {
        dispatch_source_cancel(_timeoutTimer);
        _timeoutTimer = nil;
    }
}

- (NSURLSessionConfiguration *)createSessionConfigurationForInterface {
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfig.timeoutIntervalForRequest = self.request.timeout;
    sessionConfig.timeoutIntervalForResource = self.request.timeout;
    NSString *currentInterfaceName = self.interfaceInfo[@"name"];
    
    if ([currentInterfaceName hasPrefix:@"en"]) {
        sessionConfig.networkServiceType = NSURLNetworkServiceTypeVideo;
        sessionConfig.allowsCellularAccess = NO;
    } else if ([currentInterfaceName hasPrefix:@"pdp_ip"]) {
        sessionConfig.networkServiceType = NSURLNetworkServiceTypeVoIP;
        sessionConfig.allowsCellularAccess = YES;
    } else {
        sessionConfig.networkServiceType = NSURLNetworkServiceTypeDefault;
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
    // 构建Session配置
    NSURLSessionConfiguration *sessionConfig = [self createSessionConfigurationForInterface];
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 1;
    queue.name = [NSString stringWithFormat:@"CLSHttpingQueue.%@", self.interfaceInfo[@"name"]];
    self.urlSession = [NSURLSession sessionWithConfiguration:sessionConfig
                                                   delegate:self
                                              delegateQueue:queue];

    // 校验URL
    NSURL *url = [NSURL URLWithString:self.request.domain];
    if (!url) {
        NSError *error = [NSError errorWithDomain:@"CLSHttpingErrorDomain"
                                              code:-2
                                          userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}];
        [self completeWithError:error];
        return;
    }

    // 构建请求
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = self.request.timeout;
    [request setValue:@"CLSHttping/2.0.0" forHTTPHeaderField:@"User-Agent"];
    [request setValue:self.interfaceInfo[@"name"] forHTTPHeaderField:@"X-Network-Interface"];

    // 设置超时定时器
    [self setupTimeoutTimer];
    
    // 启动任务
    self.taskStartTime = CFAbsoluteTimeGetCurrent();
    NSURLSessionDataTask *task = [self.urlSession dataTaskWithRequest:request];
    [task resume];
}

- (void)setupTimeoutTimer {
    if (_timeoutTimer) {
        dispatch_source_cancel(_timeoutTimer);
    }

    _timeoutTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (_timeoutTimer) {
        dispatch_source_set_timer(_timeoutTimer,
                                 dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.request.timeout * NSEC_PER_SEC)),
                                 DISPATCH_TIME_FOREVER, 0);

        __weak __typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(_timeoutTimer, ^{
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                NSError *timeoutError = [NSError errorWithDomain:@"CLSHttpingErrorDomain"
                                                          code:-1
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Request timeout"}];
                [strongSelf completeWithError:timeoutError];
            }
        });
        dispatch_resume(_timeoutTimer);
    }
}

- (void)completeWithError:(NSError *)error {
    if (_timeoutTimer) {
        dispatch_source_cancel(_timeoutTimer);
        _timeoutTimer = nil;
    }

    // 直接生成最终上报字典
    NSDictionary *finalReportDict = [self buildFinalReportDictWithTask:nil error:error];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionHandler) {
            self.completionHandler(finalReportDict, error);
            self.completionHandler = nil;
        }
        [self.urlSession finishTasksAndInvalidate];
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
    if (_timeoutTimer) {
        dispatch_source_cancel(_timeoutTimer);
        _timeoutTimer = nil;
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
    
    // DNS耗时
    if (transaction.domainLookupStartDate && transaction.domainLookupEndDate) {
        NSTimeInterval dnsResolutionTime = [transaction.domainLookupEndDate timeIntervalSinceDate:transaction.domainLookupStartDate] * 1000;
        metrics[@"dnsTime"] = @(dnsResolutionTime);

        CFAbsoluteTime dnsStartAbsoluteTime = [transaction.domainLookupStartDate timeIntervalSinceReferenceDate];
        NSTimeInterval waitDnsTime = (dnsStartAbsoluteTime - self.taskStartTime) * 1000;
        metrics[@"waitDnsTime"] = @(waitDnsTime);

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
        metrics[@"tcpTime"] = @(tcpTime);
        metrics[@"connectStart"] = [CLSStringUtils formatDateToMillisecondString:transaction.connectStartDate];
        // TCP结束时间：HTTPS=SSL开始时间，HTTP=connectEndDate
        NSDate *tcpEndDate = transaction.secureConnectionStartDate ?: transaction.connectEndDate;
        metrics[@"connectEnd"] = [CLSStringUtils formatDateToMillisecondString:tcpEndDate];
    } else {
        metrics[@"tcpTime"] = @(0);
        metrics[@"connectStart"] = @"";
        metrics[@"connectEnd"] = @"";
    }

    // SSL耗时
    if (transaction.secureConnectionStartDate && transaction.secureConnectionEndDate) {
        NSTimeInterval sslTime = [transaction.secureConnectionEndDate timeIntervalSinceDate:transaction.secureConnectionStartDate] * 1000;
        metrics[@"sslTime"] = @(sslTime);
        metrics[@"secureConnectStart"] = [CLSStringUtils formatDateToMillisecondString:transaction.secureConnectionStartDate];
        metrics[@"secureConnectEnd"] = [CLSStringUtils formatDateToMillisecondString:transaction.secureConnectionEndDate];
    }else{
        metrics[@"sslTime"] = @(0);
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
        metrics[@"firstByteTime"] = @(firstByteTime);
    } else if (transaction.connectEndDate && transaction.responseStartDate) {
        // HTTP场景：连接建立 = TCP结束时间
        NSTimeInterval firstByteTime = [transaction.responseStartDate timeIntervalSinceDate:transaction.connectEndDate] * 1000;
        metrics[@"firstByteTime"] = @(firstByteTime);
    } else {
        metrics[@"firstByteTime"] = @(0); // 无有效数据
    }
    
    // 2. 新增allByteTime独立计算（连接建立 → 所有响应）
    if (transaction.secureConnectionEndDate && transaction.responseEndDate) {
        // HTTPS场景
        NSTimeInterval allByteTime = [transaction.responseEndDate timeIntervalSinceDate:transaction.secureConnectionEndDate] * 1000;
        metrics[@"allByteTime"] = @(allByteTime);
    } else if (transaction.connectEndDate && transaction.responseEndDate) {
        // HTTP场景
        NSTimeInterval allByteTime = [transaction.responseEndDate timeIntervalSinceDate:transaction.connectEndDate] * 1000;
        metrics[@"allByteTime"] = @(allByteTime);
    } else {
        metrics[@"allByteTime"] = @(0); // 无有效数据
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
    // -------------------------- 1. 构建原netOrigin核心字段 --------------------------
    NSString *remoteAddr = self.timingMetrics[@"remoteAddr"] ?: @"";
    NSURL *requestURL = [NSURL URLWithString:self.request.domain];
    NSString *domain = requestURL.host ?: @"";
    
    // HTTP状态码处理
    NSInteger statusCode = -2; // 无响应默认值
    if (response) {
        statusCode = (response.statusCode >= 100 && response.statusCode <= 599) ? response.statusCode : -1;
    }
    
    // 时间戳统一计算
    NSTimeInterval timestamp = [NSDate date].timeIntervalSince1970 * 1000;
    NSTimeInterval startDateMs = self.taskStartTime * 1000;
    
    // 带宽计算（避免除0）
    double bandwidth = self.receivedBytes / MAX((totalTime / 1000), 0.001);
    
    // 错误信息处理
    NSInteger errorCode = 0;
    NSString *errorMessage = @"";
    if (error) {
        errorCode = error.code;
        errorMessage = error.localizedDescription ?: @"";
    }

    // 基础网络指标（原netOrigin）
    NSDictionary *netOrigin = @{
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
        @"timestamp": @(timestamp),
        @"startDate": @(startDateMs),
        @"ts": @(startDateMs),
        @"waitDnsTime": self.timingMetrics[@"waitDnsTime"] ?: @0,
        @"dnsTime": self.timingMetrics[@"dnsTime"] ?: @0,
        @"tcpTime": self.timingMetrics[@"tcpTime"] ?: @0,
        @"sslTime": self.timingMetrics[@"sslTime"] ?: @0,
        @"firstByteTime": self.timingMetrics[@"firstByteTime"] ?: @0,
        @"sendBytes": self.timingMetrics[@"sendBytes"] ?: @0,
        @"receiveBytes": @(self.receivedBytes),
        @"allByteTime": self.timingMetrics[@"allByteTime"] ?: @0,
        @"bandwidth": @(bandwidth),
        @"requestTime": @(totalTime),
        @"httpCode": @(statusCode),
        @"httpProtocol": response.allHeaderFields[@"Version"] ?: @"unknown",
        @"interface_ip": self.interfaceInfo[@"ip"] ?: @"",
        @"interface_type": self.interfaceInfo[@"type"] ?: @"",
        @"interface_family": self.interfaceInfo[@"family"] ?: @"",
        @"err_code": @(errorCode),
        @"error_message": errorMessage
    };
    
    // -------------------------- 2. 合并原resultDict的基础字段 --------------------------
    finalReportDict[@"pageName"] = self.request.pageName ?: @"";
    finalReportDict[@"totalTime"] = @(totalTime);
    
    // -------------------------- 3. 合并扩展字段 --------------------------
    // 构建headers
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    [response.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString *lowercaseKey = [key lowercaseString];
        headers[lowercaseKey] = obj;
    }];
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
    finalReportDict[@"userEx"] = self.request.userEx ?: @{};
    
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
    NSArray<NSDictionary *> *availableInterfaces = [CLSNetworkUtils getAvailableInterfacesForType];
    for (NSDictionary *currentInterface in availableInterfaces) {
        NSLog(@"interface:%@", currentInterface);
        CLSSpanBuilder *builder = [[CLSSpanBuilder builder] initWithName:@"network_diagnosis" provider:[[CLSSpanProviderDelegate alloc] init]];
        [builder setURL:self.request.domain];
        [builder setpageName:self.request.pageName];
        // 设置自定义traceId
        if (self.request.traceId) {
            [builder setTraceId:self.request.traceId];
        }
        [self startHttpingWithCompletion:currentInterface completion:^(NSDictionary *finalReportDict, NSError *error) {
            // 上报并获取返回字典
            NSDictionary *d = [builder report:self.topicId reportData:finalReportDict];
            
            // 使用report返回的字典构建响应
            CLSResponse *completionResult = [CLSResponse complateResultWithContent:d ?: @{}];
            
            // 回调返回结果
            if (complate) {
                complate(completionResult);
            }
        }];
        
        // 非多端口检测，仅执行第一个接口
        if (!self.request.enableMultiplePortsDetect) {
            break;
        }
    }
}

@end
