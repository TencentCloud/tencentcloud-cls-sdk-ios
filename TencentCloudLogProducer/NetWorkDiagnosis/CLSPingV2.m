//
//  CLSPing.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/16.
//

#import <Foundation/Foundation.h>
#import "CLSPingV2.h"
#import "CLSRequestValidator.h"
#import "CLSNetworkUtils.h"
#import <netinet/in.h>
#import <arpa/inet.h>
#import <netdb.h>
#import "CLSIdGenerator.h"
#import "CLSSPanBuilder.h"
#import "CLSCocoa.h"
#import "network_ios/cls_ping_detector.h"
#import "ClsNetworkDiagnosis.h"  // 引入以获取全局 userEx

// 常量定义（统一维护，便于修改）
static NSString *const kPINGLogPrefix = @"[PING检测]";
static const NSUInteger kPINGJsonBufferSize = 2048;

@interface CLSMultiInterfacePing ()
@property (nonatomic, strong) NSDictionary *interfaceInfo;
@end

@implementation CLSMultiInterfacePing

- (instancetype)initWithRequest:(CLSPingRequest *)request {
    self = [super init];
    if (self) {
        _request = request;
    }
    return self;
}

#pragma mark - 单网卡PING检测
- (void)startPingWithInterface:(NSDictionary *)interfaceInfo completion:(CompleteCallback)completion {
    // 1. 空值校验：网卡信息为空直接回调空结果
    if (!interfaceInfo) {
        NSLog(@"%@ 网卡信息为空，跳过检测", kPINGLogPrefix);
        CLSResponse *emptyResult = [CLSResponse complateResultWithContent:@{}];
        if (completion) completion(emptyResult);
        return;
    }
    
    // 2. 核心参数校验：request/domain 为空直接返回
    if (!self.request) {
        NSLog(@"%@ 检测请求为空，跳过检测", kPINGLogPrefix);
        CLSResponse *emptyResult = [CLSResponse complateResultWithContent:@{}];
        if (completion) completion(emptyResult);
        return;
    }
    NSString *domainStr = self.request.domain ?: @"";
    if (domainStr.length == 0) {
        NSLog(@"%@ 检测域名为空，跳过检测", kPINGLogPrefix);
        CLSResponse *emptyResult = [CLSResponse complateResultWithContent:@{}];
        if (completion) completion(emptyResult);
        return;
    }
    const char *domain = [domainStr UTF8String];
    NSString *interfaceName = interfaceInfo[@"name"] ?: @"未知";
    self.interfaceInfo = [interfaceInfo copy];
    
    // 2. 初始化PING配置（关键：memset清空结构体）
    cls_ping_detector_config config;
    memset(&config, 0, sizeof(config)); // 必须初始化，避免残留值
    config.packet_size = self.request.size;
    config.ttl = 64;
    // 配置参数（timeout 已经是毫秒单位，直接使用）
    config.timeout_ms = self.request.timeout;
    config.interval_ms = self.request.interval;
    config.times = self.request.maxTimes;
    config.prefer = self.request.prefer;  // 使用 request 中的 prefer 配置
    
    // 4. 处理网卡下标（unsigned int 类型适配，空值兜底）
    NSNumber *indexNum = interfaceInfo[@"index"];
    unsigned int interfaceIndex = 0;
    if (indexNum && [indexNum isKindOfClass:[NSNumber class]]) {
        NSInteger tempIndex = [indexNum integerValue];
        interfaceIndex = (tempIndex > 0) ? (unsigned int)tempIndex : 0;
    }
    config.interface_index = interfaceIndex;
    
    // 5. 执行PING检测（异常捕获，避免流程中断）
    cls_ping_detector_result result;
    cls_ping_detector_error_code code = cls_ping_detector_error_unknown_error;
    @try {
        code = cls_ping_detector_perform_ping(domain, &config, &result);
    } @catch (NSException *exception) {
        NSLog(@"%@ 网卡%@（域名%@）：检测抛出异常：%@", kPINGLogPrefix, interfaceName, domainStr, exception);
        code = cls_ping_detector_error_unknown_error;
    }
    
    // 6. 转换检测结果为JSON字符串
    char json_buffer[kPINGJsonBufferSize] = {0};
    (void)cls_ping_detector_result_to_json(&result, json_buffer, sizeof(json_buffer));
    
    // 7. 错误日志增强（补充上下文）
    if (code != cls_ping_detector_error_success) {
        NSLog(@"%@ 网卡%@（域名%@）：检测失败，错误码：%d", kPINGLogPrefix, interfaceName, domainStr, code);
    }
    
    // 8. 解析JSON并构建上报数据
    NSString *jsonString = [[NSString alloc] initWithCString:json_buffer encoding:NSUTF8StringEncoding];
    NSLog(@"%@ 网卡%@（域名%@）：检测结果：%@", kPINGLogPrefix, interfaceName, domainStr, jsonString);
    NSDictionary *reportData = [self buildReportDataFromPingResult:jsonString];
    
    // 9. 上报链路数据（语义化日志，避免冗余构建）
    CLSSpanBuilder *builder = [[CLSSpanBuilder builder] initWithName:@"network_diagnosis" provider:[[CLSSpanProviderDelegate alloc] init]];
    [builder setURL:domainStr];
    [builder setpageName:self.request.pageName];
    // 设置自定义traceId
    if (self.request.traceId) {
        [builder setTraceId:self.request.traceId];
    }
    NSDictionary *d = [builder report:self.topicId reportData:reportData];
    
    // 10. 回调结果（空值兜底）
    CLSResponse *callbackResult = [CLSResponse complateResultWithContent:d ?: @{}];
    if (completion) {
        completion(callbackResult);
    }
}

#pragma mark - 构建PING上报数据
- (NSDictionary *)buildReportDataFromPingResult:(NSString *)sectionResult {
    // 1. 空值校验
    if (!sectionResult || sectionResult.length == 0) {
        NSLog(@"%@ 上报数据：JSON字符串为空", kPINGLogPrefix);
        return @{};
    }
    
    // 2. JSON字符串转NSData（UTF-8编码，空值兜底）
    NSData *jsonData = [sectionResult dataUsingEncoding:NSUTF8StringEncoding];
    if (!jsonData) {
        NSLog(@"%@ 上报数据：JSON转Data失败，字符串：%@", kPINGLogPrefix, sectionResult);
        return @{};
    }
    
    // 3. 解析JSON为可变字典（带错误处理）
    NSError *parseError = nil;
    id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData
                                                    options:NSJSONReadingMutableContainers
                                                      error:&parseError];
    
    // 解析错误兜底
    if (parseError) {
        NSLog(@"%@ 上报数据：JSON解析失败：%@，原始字符串：%@", kPINGLogPrefix, parseError.localizedDescription, sectionResult);
        return @{};
    }
    
    // 4. 校验解析结果类型（必须是字典）
    if (![jsonObject isKindOfClass:[NSMutableDictionary class]]) {
        NSLog(@"%@ 上报数据：JSON根节点非字典，实际类型：%@", kPINGLogPrefix, [jsonObject class]);
        return @{};
    }
    
    NSMutableDictionary *reportData = (NSMutableDictionary *)jsonObject;
    NSLog(@"%@ 上报数据：解析后的原始PING字典：%@", kPINGLogPrefix, reportData);
    
    // 5. 追加通用字段（空值兜底，避免崩溃）
    reportData[@"appKey"] = self.request.appKey;
    reportData[@"src"] = @"app";
    reportData[@"trace_id"] = CLSIdGenerator.generateTraceId ?: @""; // 核心修复：nil兜底
    reportData[@"netInfo"] = [CLSNetworkUtils buildEnhancedNetworkInfoWithInterfaceType:self.interfaceInfo[@"type"]
                                                                networkAppId:self.networkAppId
                                                                       appKey:self.appKey
                                                                         uin:self.uin
                                                                     endpoint:self.endPoint
                                                                interfaceDNS:self.interfaceInfo[@"dns"]];
    reportData[@"detectEx"] = self.request.detectEx ?: @{};
    reportData[@"userEx"] = [[ClsNetworkDiagnosis sharedInstance] getUserEx] ?: @{};  // 从全局获取
    
    return [reportData copy];
}

#pragma mark - 启动多网卡PING检测
- (void)start:(CompleteCallback)completion {
    // 参数合法性校验
    NSError *validationError = nil;
    if (![CLSRequestValidator validatePingRequest:self.request error:&validationError]) {
        NSLog(@"❌ Ping探测参数校验失败: %@", validationError.localizedDescription);
        if (completion) {
            CLSResponse *errorResponse = [CLSResponse complateResultWithContent:@{
                @"error": @"参数校验失败",
                @"error_message": validationError.localizedDescription,
                @"error_code": @(validationError.code)
            }];
            completion(errorResponse);
        }
        return;
    }
    
    NSLog(@"✅ Ping探测参数: maxTimes=%d, timeout=%dms, size=%d bytes, interval=%dms, prefer=%d", 
          self.request.maxTimes, self.request.timeout, self.request.size, self.request.interval, self.request.prefer);
    
    // 获取可用网卡列表（空值兜底）
    NSArray<NSDictionary *> *availableInterfaces = [CLSNetworkUtils getAvailableInterfacesForType];
    if (availableInterfaces.count == 0) {
        NSLog(@"%@ 无可用网卡接口", kPINGLogPrefix);
        CLSResponse *emptyResult = [CLSResponse complateResultWithContent:@{}];
        completion(emptyResult);
        return;
    }
    
    // 遍历网卡执行检测
    for (NSDictionary *interfaceInfo in availableInterfaces) {
        NSString *interfaceName = interfaceInfo[@"name"] ?: @"未知";
        NSLog(@"%@ 开始检测网卡：%@", kPINGLogPrefix, interfaceName);
        [self startPingWithInterface:interfaceInfo completion:completion];
        
        // 非多端口检测时，仅检测第一个网卡后退出
        if (self.request && !self.request.enableMultiplePortsDetect) {
            NSLog(@"%@ 非多端口检测模式，终止后续网卡检测", kPINGLogPrefix);
            break;
        }
    }
}

@end
