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
    // 配置网络超时参数（timeout 从秒转换为秒，NSURLSession 使用秒单位）
    sessionConfig.timeoutIntervalForRequest = self.request.timeout;
    sessionConfig.timeoutIntervalForResource = self.request.timeout;
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

    // ✅ 移除外层定时器，只依赖 NSURLSession 的超时控制
    // NSURLSession 的 timeoutIntervalForRequest 已提供系统级超时机制
    // 外层定时器会与重试逻辑冲突，且在重试时不会正确重置
    
    // 启动任务（依赖 NSURLSession 超时，外层控制 maxRetries 重试）
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
    
    // 错误信息处理（增强逻辑）
    NSInteger errorCode = 0;
    NSString *errorMessage = @"";
    
    if (error) {
        // 场景1：网络错误（超时、连接失败等）
        if ([error.domain isEqualToString:NSURLErrorDomain]) {
            errorCode = 2000 + error.code;  // 网络错误基础码 2000 + NSURLError code
            errorMessage = [NSString stringWithFormat:@"Network error: %@", error.localizedDescription];
        } else if ([error.domain isEqualToString:@"CLSHttpingErrorDomain"]) {
            // 自定义错误（超时=-1, 无效URL=-2）
            errorCode = error.code;
            errorMessage = error.localizedDescription ?: @"";
        } else {
            // 其他未知错误
            errorCode = 3000 + error.code;
            errorMessage = [NSString stringWithFormat:@"Unknown error: %@", error.localizedDescription];
        }
    } else if (statusCode >= 400) {
        // 场景2：HTTP错误状态码（4xx/5xx）
        errorCode = 1000 + statusCode;  // HTTP错误基础码 1000 + statusCode
        errorMessage = [NSString stringWithFormat:@"HTTP %ld", (long)statusCode];
    } else if (statusCode == -2) {
        // 场景3：无响应
        errorCode = -3;
        errorMessage = @"No response";
    } else if (statusCode >= 200 && statusCode < 400) {
        // 场景4：成功（2xx/3xx）
        errorCode = 0;
        errorMessage = @"Success";
    } else {
        // 场景5：异常状态码
        errorCode = -4;
        errorMessage = [NSString stringWithFormat:@"Invalid status code: %ld", (long)statusCode];
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
        @"httpProtocol": self.timingMetrics[@"httpProtocol"] ?: @"unknown",
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
    // 参数合法性校验
    NSError *validationError = nil;
    if (![CLSRequestValidator validateHttpRequest:self.request error:&validationError]) {
        NSLog(@"❌ HTTP探测参数校验失败: %@", validationError.localizedDescription);
        if (complate) {
            CLSResponse *errorResponse = [CLSResponse complateResultWithContent:@{
                @"error": @"参数校验失败",
                @"error_message": validationError.localizedDescription,
                @"error_code": @(validationError.code)
            }];
            complate(errorResponse);
        }
        return;
    }
    
    // maxTimes 表示最大尝试次数（包含首次尝试）
    int maxRetries = self.request.maxTimes;
    NSLog(@"✅ HTTP探测参数: maxRetries=%d, timeout=%ds, size=%d bytes", maxRetries, self.request.timeout, self.request.size);
    
    NSArray<NSDictionary *> *availableInterfaces = [CLSNetworkUtils getAvailableInterfacesForType];
    for (NSDictionary *currentInterface in availableInterfaces) {
        NSLog(@"interface:%@", currentInterface);
        
        // 使用串行队列和信号量实现同步重试逻辑
        dispatch_queue_t retryQueue = dispatch_queue_create("com.tencent.cls.httpping.retry", DISPATCH_QUEUE_SERIAL);
        
        dispatch_async(retryQueue, ^{
            __block BOOL hasSucceeded = NO;
            
            // 执行 maxRetries 次尝试（首次 + 失败后的重试）
            for (int i = 0; i < maxRetries && !hasSucceeded; i++) {
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                
                int attemptCount = i + 1;
                NSLog(@"🔄 HTTP Ping 尝试 %d/%d", attemptCount, maxRetries);
                
                CLSSpanBuilder *builder = [[CLSSpanBuilder builder] initWithName:@"network_diagnosis" provider:[[CLSSpanProviderDelegate alloc] init]];
                [builder setURL:self.request.domain];
                [builder setpageName:self.request.pageName];
                
                [self startHttpingWithCompletion:currentInterface completion:^(NSDictionary *finalReportDict, NSError *error) {
                    // ✅ 修复：HTTP Ping 判断成功标准
                    // HTTP Ping 没有 responseNum 字段，应该根据 httpCode 和 error 判断
                    NSInteger httpCode = [finalReportDict[@"httpCode"] integerValue];
                    BOOL isHttpSuccess = (httpCode >= 200 && httpCode < 400);  // 2xx/3xx 为成功
                    
                    if (!error && isHttpSuccess) {
                        hasSucceeded = YES;
                        NSLog(@"✅ HTTP Ping 成功（第 %d 次尝试）- HTTP %ld", attemptCount, (long)httpCode);
                    } else {
                        NSLog(@"❌ HTTP Ping 失败（第 %d 次尝试）- HTTP %ld, Error: %@", 
                              attemptCount, (long)httpCode, error.localizedDescription ?: @"无响应");
                    }
                    
                    // 上报并获取返回字典
                    NSDictionary *d = [builder report:self.topicId reportData:finalReportDict];
                    
                    // 使用report返回的字典构建响应
                    CLSResponse *completionResult = [CLSResponse complateResultWithContent:d ?: @{}];
                    
                    // 回调返回结果
                    if (complate) {
                        complate(completionResult);
                    }
                    
                    // 释放信号量
                    dispatch_semaphore_signal(semaphore);
                }];
                
                // 等待当前尝试完成
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            }
        });
        
        // 非多端口检测，仅执行第一个接口
        if (!self.request.enableMultiplePortsDetect) {
            break;
        }
    }
}

@end
