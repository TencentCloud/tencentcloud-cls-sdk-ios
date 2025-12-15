//
//  CLSHttpingV2.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/13.
//

#import "CLSHttpingV2.h"
#import "CLSNetworkUtils.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CLSResponse.h"
#import "CLSIdGenerator.h"
#import "CLSSPanBuilder.h"
#import "CLSCocoa.h"

@implementation CLSHttpingResult

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

@interface CLSMultiInterfaceHttping () <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@property (nonatomic, strong) NSURLSession *urlSession;
@property (nonatomic, strong) NSMutableDictionary *timingMetrics;
@property (nonatomic, assign) CFAbsoluteTime startTime;
@property (nonatomic, assign) CFAbsoluteTime requestPreparationTime;
//@property (nonatomic, assign) NSUInteger sentBytes;
@property (nonatomic, assign) NSUInteger receivedBytes;
@property (nonatomic, strong) NSMutableData *responseData;
@property (nonatomic, copy) void (^completionHandler)(CLSHttpingResult *result, NSError *error);
//@property (nonatomic, strong) NSString *currentInterface;
@property (nonatomic, strong) NSDictionary *interfaceInfo;
@property (nonatomic, strong) dispatch_source_t timeoutTimer;

@end

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
     }else {
         // 未知或其他接口类型，使用默认配置
         sessionConfig.networkServiceType = NSURLNetworkServiceTypeDefault;
     }

    // 设置多路径服务以支持多网卡
    if (@available(iOS 11.0, *)) {
        // 判断多网卡开关：未开启则禁用多路径服务
        if (self.request.enableMultiplePortsDetect && sessionConfig.networkServiceType == NSURLNetworkServiceTypeDefault) {
            sessionConfig.multipathServiceType = NSURLSessionMultipathServiceTypeHandover;
        } else {
            // 单网卡场景：显式禁用多路径服务（默认值为NSURLSessionMultipathServiceTypeNone，此处显式设置更清晰）
            sessionConfig.multipathServiceType = NSURLSessionMultipathServiceTypeNone;
        }
    }

    return sessionConfig;
}

#pragma mark - HTTP Ping 执行

- (void)startHttpingWithCompletion: (NSDictionary *)currentInterface completion:(void (^)(CLSHttpingResult *result, NSError *error))completion; {
    self.completionHandler = completion;
    self.startTime = CFAbsoluteTimeGetCurrent();
    self.requestPreparationTime = CFAbsoluteTimeGetCurrent();
    self.interfaceInfo = [currentInterface copy];

    // 创建会话配置
    NSURLSessionConfiguration *sessionConfig = [self createSessionConfigurationForInterface];

    // 创建会话队列
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 1;
    queue.name = [NSString stringWithFormat:@"CLSHttpingQueue.%@", self.interfaceInfo[@"name"]];

    // 创建URLSession
    self.urlSession = [NSURLSession sessionWithConfiguration:sessionConfig
                                                   delegate:self
                                              delegateQueue:queue];

    // 创建请求
    NSURL *url = [NSURL URLWithString:self.request.domain];
    if (!url) {
        NSError *error = [NSError errorWithDomain:@"CLSHttpingErrorDomain"
                                              code:-2
                                          userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}];
        [self completeWithError:error];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = self.request.timeout;

    // 添加自定义Header
    [request setValue:@"CLSHttping/2.0.0" forHTTPHeaderField:@"User-Agent"];
    [request setValue:self.interfaceInfo[@"name"] forHTTPHeaderField:@"X-Network-Interface"];

    // 设置超时定时器
    [self setupTimeoutTimer];

    // 启动任务
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

    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
    NSTimeInterval totalTime = (endTime - self.startTime) * 1000;

    CLSHttpingResult *result = [self buildResultWithTask:nil error:error totalTime:totalTime];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionHandler) {
            self.completionHandler(result, error);
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

    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
    NSTimeInterval totalTime = (endTime - self.startTime) * 1000;

    CLSHttpingResult *result = [self buildResultWithTask:task error:error totalTime:totalTime];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionHandler) {
            self.completionHandler(result, error);
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

#pragma mark - 指标记录和结果构建

- (void)recordTimingMetrics:(NSURLSessionTaskTransactionMetrics *)transaction {
    // 记录详细的时序指标
    NSMutableDictionary *metrics = [NSMutableDictionary dictionary];
    if (transaction.domainLookupStartDate && transaction.domainLookupEndDate) {
        NSTimeInterval dnsResolutionTime = [transaction.domainLookupEndDate timeIntervalSinceDate:transaction.domainLookupStartDate] * 1000;
        metrics[@"dnsTime"] = @(dnsResolutionTime);

        CFAbsoluteTime dnsStartAbsoluteTime = [transaction.domainLookupStartDate timeIntervalSinceReferenceDate];
        NSTimeInterval waitDnsTime = (dnsStartAbsoluteTime - self.requestPreparationTime) * 1000;
        metrics[@"waitDnsTime"] = @(waitDnsTime);

        metrics[@"dnsStart"] = [CLSStringUtils formatDateToMillisecondString:transaction.domainLookupStartDate];
        metrics[@"dnsEnd"] = [CLSStringUtils formatDateToMillisecondString:transaction.domainLookupEndDate];
    }

    if (transaction.connectStartDate && transaction.connectEndDate) {
        NSTimeInterval tcpTime = [transaction.connectEndDate timeIntervalSinceDate:transaction.connectStartDate] * 1000;
        metrics[@"tcpTime"] = @(tcpTime);
        metrics[@"connectStart"] = [CLSStringUtils formatDateToMillisecondString:transaction.connectStartDate];
        metrics[@"connectEnd"] = [CLSStringUtils formatDateToMillisecondString:transaction.connectEndDate];
    }

    if (transaction.secureConnectionStartDate && transaction.secureConnectionEndDate) {
        NSTimeInterval sslTime = [transaction.secureConnectionEndDate timeIntervalSinceDate:transaction.secureConnectionStartDate] * 1000;
        metrics[@"sslTime"] = @(sslTime);
        metrics[@"secureConnectStart"] = [CLSStringUtils formatDateToMillisecondString:transaction.secureConnectionStartDate];
        metrics[@"secureConnectEnd"] = [CLSStringUtils formatDateToMillisecondString:transaction.secureConnectionEndDate];
    }

    if (transaction.requestStartDate && transaction.requestEndDate) {
        NSTimeInterval requestTime = [transaction.requestEndDate timeIntervalSinceDate:transaction.requestStartDate] * 1000;
        NSDate *preparationDate = [NSDate dateWithTimeIntervalSinceReferenceDate:self.requestPreparationTime];
        metrics[@"callStart"] = [CLSStringUtils formatDateToMillisecondString:preparationDate];
        metrics[@"requestHeaderStart"] = [CLSStringUtils formatDateToMillisecondString:transaction.requestStartDate];
        metrics[@"requestHeaderEnd"] = [CLSStringUtils formatDateToMillisecondString:transaction.requestEndDate];
    }

    if (transaction.responseStartDate && transaction.responseEndDate) {
        NSTimeInterval responseTime = [transaction.responseEndDate timeIntervalSinceDate:transaction.responseStartDate] * 1000;
        metrics[@"callEnd"] = [CLSStringUtils formatDateToMillisecondString:transaction.responseEndDate];
        metrics[@"responseHeadersStart"] = [CLSStringUtils formatDateToMillisecondString:transaction.responseStartDate];
        metrics[@"responseHeaderEnd"] = [CLSStringUtils formatDateToMillisecondString:transaction.responseStartDate];
        metrics[@"responseBodyStart"] = [CLSStringUtils formatDateToMillisecondString:transaction.responseStartDate];
        metrics[@"responseBodyEnd"] = [CLSStringUtils formatDateToMillisecondString:transaction.responseEndDate];
        
        CFAbsoluteTime firstAbsoluteTime = [transaction.responseStartDate timeIntervalSinceReferenceDate];
        NSTimeInterval firstByteTime = (firstAbsoluteTime - self.requestPreparationTime) * 1000;
        metrics[@"firstByteTime"] = @(firstByteTime);
    }

    metrics[@"connectionReleased"] = [CLSStringUtils formatDateToMillisecondString:transaction.responseEndDate];

    // 远程地址
    NSString *remoteIP = transaction.remoteAddress;
    if (remoteIP) {
         metrics[@"remoteAddr"] = remoteIP;
    }

    //发送字节数
    NSUInteger sentBytes = transaction.countOfRequestHeaderBytesSent + transaction.countOfRequestBodyBytesSent;
    if(sentBytes != 0){
        metrics[@"sendBytes"] = @(sentBytes);
    }

    [self.timingMetrics addEntriesFromDictionary:metrics];
}

- (CLSHttpingResult *)buildResultWithTask:(NSURLSessionTask *)task
                                    error:(NSError *)error
                                totalTime:(NSTimeInterval)totalTime {

    CLSHttpingResult *result = [[CLSHttpingResult alloc] init];
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;

    // 基础信息
    result.netType = @"http";
    result.pageName = self.request.pageName;
    result.eventType = @"net_d";

    // 详细网络信息（包含多网卡信息）
    result.netOrigin = [self buildNetOriginWithResponse:response totalTime:totalTime];
    result.headers = [self buildHeadersWithResponse:response];
    result.desc = [self buildTimeDescription];
    result.netInfo = [self buildEnhancedNetworkInfo];
    result.detectEx = self.request.detectEx;
    result.userEx = self.request.userEx;

    // 状态信息
    result.success = (error == nil);
    result.error = error;
    result.totalTime = totalTime;

    return result;
}

- (NSDictionary *)buildEnhancedNetworkInfo {
    NSMutableDictionary *networkInfo = [CLSNetworkUtils getNetworkEnvironmentInfo:self.interfaceInfo[@"type"] networkAppId:self.networkAppId appKey:self.appKey uin:self.uin endpoint:self.endPoint].mutableCopy;
    if(networkInfo.count > 0){
        networkInfo[@"dns"] = self.interfaceInfo[@"dns"] ?:@"";
    }
    
    return [networkInfo copy];
}

- (NSDictionary *)buildNetOriginWithResponse:(NSHTTPURLResponse *)response
                                   totalTime:(NSTimeInterval)totalTime {

    NSString *remoteAddr = self.timingMetrics[@"remoteAddr"] ?:@"";
    NSNumber *dnsTime = self.timingMetrics[@"dnsTime"] ?: @0;
    NSNumber *waitDnsTime = self.timingMetrics[@"waitDnsTime"] ?: @0;
    NSNumber *tcpTime = self.timingMetrics[@"tcpTime"] ?: @0;
    NSNumber *sslTime = self.timingMetrics[@"sslTime"] ?: @0;
    NSNumber *firstByteTime = self.timingMetrics[@"firstByteTime"] ?: @0;
    NSNumber *sendBytes = self.timingMetrics[@"sendBytes"] ?: @0;
    NSNumber *httpCode = @0; // 默认值兜底（避免 nil）
    if (response) {
        NSInteger statusCode = response.statusCode;
        // 校验 HTTP 状态码合法性（100~599 是标准范围）
        if (statusCode >= 100 && statusCode <= 599) {
            httpCode = @(statusCode);
        } else {
            httpCode = @(-1); // 非法状态码标记为 -1，便于排查
        }
    } else {
        httpCode = @(-2); // 无响应标记为 -2，区分「无响应」和「非法状态码」
    }
    NSString *httpProtocol = response ? (response.allHeaderFields[@"Version"] ?: @"unknown") : @"unknown";
    NSMutableDictionary *netOrigin = [NSMutableDictionary dictionaryWithDictionary:@{
        @"method": @"http",
        @"url": self.request.domain ?: @"",
        @"trace_id": CLSIdGenerator.generateTraceId,
        @"appKey": self.request.appKey ?: @"",
        @"host_ip": remoteAddr ?: @"",
        @"timestamp": @([NSDate date].timeIntervalSince1970 * 1000),
        @"startDate": @(self.startTime * 1000),
        @"waitDnsTime": waitDnsTime,
        @"dnsTime": dnsTime,
        @"domain": [NSURL URLWithString:self.request.domain].host ?: @"",
        @"remoteAddr": remoteAddr ?: @"",
        @"tcpTime": tcpTime,
        @"sslTime": sslTime,
        @"sendBytes": sendBytes,
        @"firstByteTime": firstByteTime,
        @"httpCode": httpCode,
        @"httpProtocol": httpProtocol,
        @"receiveBytes": @(self.receivedBytes),
        @"allByteTime": @(totalTime),
        @"bandwidth": @(self.receivedBytes / MAX((totalTime / 1000), 0.001)),
        @"requestTime": @(totalTime),
        @"interface": self.interfaceInfo[@"type"],
        @"src": @"app",
        @"ts": @(self.startTime * 1000),
        @"sdkVer": @"2.0.0",
        @"sdkBuild": [CLSNetworkUtils getSDKBuildTime]
    }];

    // 添加接口详细信息
    if (self.interfaceInfo.count > 0) {
        netOrigin[@"interface_ip"] = self.interfaceInfo[@"ip"] ?: @"";
        netOrigin[@"interface_type"] = self.interfaceInfo[@"type"] ?: @"";
        netOrigin[@"interface_family"] = self.interfaceInfo[@"family"] ?: @"";
    }

    return [netOrigin copy];
}

- (NSDictionary *)buildHeadersWithResponse:(NSHTTPURLResponse *)response {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];

    [response.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString *lowercaseKey = [key lowercaseString];
        headers[lowercaseKey] = obj;
    }];

    // 添加接口信息到headers
    headers[@"x-network-interface"] = self.interfaceInfo[@"name"];
    if (self.interfaceInfo[@"ip"]) {
        headers[@"x-source-ip"] = self.interfaceInfo[@"ip"];
    }

    return headers;
}

- (NSDictionary *)buildTimeDescription {
    NSMutableDictionary *timeDesc = [NSMutableDictionary dictionaryWithDictionary:@{
        @"callStart": self.timingMetrics[@"callStart"] ?:@"",
        @"dnsStart": self.timingMetrics[@"dnsStart"] ?:@"",
        @"dnsEnd": self.timingMetrics[@"dnsEnd"] ?:@"",
        @"connectStart": self.timingMetrics[@"connectStart"] ?:@"",
        @"secureConnectStart": self.timingMetrics[@"secureConnectStart"] ?:@"",
        @"secureConnectEnd": self.timingMetrics[@"secureConnectEnd"] ?:@"",
        @"connectionAcquired": self.timingMetrics[@"connectEnd"] ?:@"",
        @"requestHeaderStart": self.timingMetrics[@"requestHeaderStart"] ?:@"",
        @"requestHeaderEnd": self.timingMetrics[@"requestHeaderEnd"] ?:@"",
        @"responseHeadersStart": self.timingMetrics[@"responseHeadersStart"] ?:@"",
        @"responseHeaderEnd": self.timingMetrics[@"responseHeaderEnd"] ?:@"",
        @"responseBodyStart": self.timingMetrics[@"responseBodyStart"] ?:@"",
        @"responseBodyEnd": self.timingMetrics[@"responseBodyEnd"] ?:@"",
        @"connectionReleased": self.timingMetrics[@"connectionReleased"] ?:@"",
        @"callEnd": self.timingMetrics[@"callEnd"] ?:@""
    }];

    return timeDesc;
}

- (BOOL)isAppInForeground {
    return [UIApplication sharedApplication].applicationState == UIApplicationStateActive;
}

- (NSDictionary *)buildReportDataFromHttpingResult:(CLSHttpingResult *)result {
    // 获取当前时间戳
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970] * 1000;

    // 构建基础信息 - 确保所有值都是JSON兼容类型
    NSMutableDictionary *reportData = [NSMutableDictionary dictionaryWithDictionary:@{
        @"method": @"http",
        @"url": [CLSStringUtils sanitizeString:result.netOrigin[@"url"]] ?: @"",
        @"trace_id": [CLSStringUtils sanitizeString:result.netOrigin[@"trace_id"]] ?: @"",
        @"appKey": [CLSStringUtils sanitizeString:result.netOrigin[@"appKey"]] ?: @"",
        @"host_ip": [CLSStringUtils sanitizeString:result.netOrigin[@"host_ip"]] ?: @"",
        @"timestamp": @(timestamp),
        @"startDate": @(timestamp),
        @"waitDnsTime": [CLSStringUtils sanitizeNumber:result.netOrigin[@"waitDnsTime"]] ?: @0,
        @"dnsTime": [CLSStringUtils sanitizeNumber:result.netOrigin[@"dnsTime"]] ?: @0,
        @"domain": [CLSStringUtils sanitizeString:result.netOrigin[@"domain"]] ?: @"",
        @"remoteAddr": [CLSStringUtils sanitizeString:result.netOrigin[@"remoteAddr"]] ?: @"",
        @"tcpTime": [CLSStringUtils sanitizeNumber:result.netOrigin[@"tcpTime"]] ?: @0,
        @"sslTime": [CLSStringUtils sanitizeNumber:result.netOrigin[@"sslTime"]] ?: @0,
        @"sendBytes": [CLSStringUtils sanitizeNumber:result.netOrigin[@"sendBytes"]] ?: @0,
        @"firstByteTime": [CLSStringUtils sanitizeNumber:result.netOrigin[@"firstByteTime"]] ?: @0,
        @"httpCode": [CLSStringUtils sanitizeNumber:result.netOrigin[@"httpCode"]] ?: @0,
        @"httpProtocol": [CLSStringUtils sanitizeString:result.netOrigin[@"httpProtocol"]] ?: @"",
        @"receiveBytes": [CLSStringUtils sanitizeNumber:result.netOrigin[@"receiveBytes"]] ?: @0,
        @"allByteTime": [CLSStringUtils sanitizeNumber:result.netOrigin[@"allByteTime"]] ?: @0,
        @"bandwidth": [CLSStringUtils sanitizeNumber:result.netOrigin[@"bandwidth"]] ?: @0,
        @"requestTime": [CLSStringUtils sanitizeNumber:result.netOrigin[@"requestTime"]] ?: @0,
        @"src": @"app",
        @"ts": @(timestamp)
    }];

    // 添加headers - 确保headers中的所有值都是字符串
    reportData[@"headers"] = [CLSStringUtils sanitizeHeaders:result.headers];

    // 添加desc - 确保所有时间戳都是字符串格式
    reportData[@"desc"] = [CLSStringUtils sanitizeDesc:result.desc];

    // 添加网络信息 - 确保所有值都是字符串或数字
    reportData[@"netInfo"] = [CLSStringUtils sanitizeDictionary:result.netInfo];

    // 添加检测扩展信息 - 确保所有值都是字符串
    reportData[@"detectEx"] = [CLSStringUtils sanitizeDictionary:result.detectEx];

    // 添加用户扩展信息 - 确保所有值都是字符串
    reportData[@"userEx"] = [CLSStringUtils sanitizeDictionary:result.userEx];

    return [reportData copy];
}

- (void)start:(CLSHttpRequest *) request complate:(CompleteCallback)complate{

    NSArray<NSDictionary *> *availableInterfaces = [CLSNetworkUtils getAvailableInterfacesForType];

    for (NSDictionary *currentInterface in availableInterfaces) {
        NSLog(@"interface:%@",currentInterface);
        CLSSpanBuilder *builder = [[CLSSpanBuilder builder] initWithName:@"network_diagnosis" provider:[[CLSSpanProviderDelegate alloc] init]];
        [builder setURL:request.domain];
        [self startHttpingWithCompletion:currentInterface completion:^(CLSHttpingResult *result, NSError *error) {
            NSDictionary *reportData = [self buildReportDataFromHttpingResult:result];
            CLSResponse *complateResult = [CLSResponse complateResultWithContent:reportData];
            if (complate) {
                complate(complateResult);
            }
            [builder report:self.topicId reportData:reportData];
        }];
        if(request.enableMultiplePortsDetect == NO){
            break;
        }
    }

}

@end
