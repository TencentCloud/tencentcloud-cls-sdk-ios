#import "CLSMtrping.h"
#import "CLSRequestValidator.h"
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
#import "network_ios/cls_mtr_detector.h"
#import "ClsNetworkDiagnosis.h"  // 引入以获取全局 userEx

static NSString *const kMtrLogPrefix = @"[MTR检测]";
static const NSUInteger kMTRJsonBufferSize = 65535;

@interface CLSMultiInterfaceMtr ()
@property (nonatomic, strong) NSDictionary *interfaceInfo;
@end


@implementation CLSMultiInterfaceMtr {
    dispatch_source_t _timeoutTimer;
}

- (instancetype)initWithRequest:(CLSMtrRequest *)request {
    self = [super init];
    if (self) {
        _request = request;
    }
    return self;
}

#pragma mark - MTR探测核心逻辑
- (void)startMtrWithCompletion:(NSDictionary *)interfaceInfo completion:(CompleteCallback)completion{
    // 1. 空值校验：网卡信息为空直接回调空结果
    if (!interfaceInfo) {
        NSLog(@"%@ 网卡信息为空，跳过检测", kMtrLogPrefix);
        CLSResponse *emptyResult = [CLSResponse complateResultWithContent:@{}];
        if (completion) completion(emptyResult);
        return;
    }
    
    // 2. 核心参数校验：request/domain 为空直接返回
    if (!self.request) {
        NSLog(@"%@ 检测请求为空，跳过检测", kMtrLogPrefix);
        CLSResponse *emptyResult = [CLSResponse complateResultWithContent:@{}];
        if (completion) completion(emptyResult);
        return;
    }
    NSString *domainStr = self.request.domain ?: @"";
    if (domainStr.length == 0) {
        NSLog(@"%@ 检测域名为空，跳过检测", kMtrLogPrefix);
        CLSResponse *emptyResult = [CLSResponse complateResultWithContent:@{}];
        if (completion) completion(emptyResult);
        return;
    }
    const char *domain = [domainStr UTF8String];
    NSString *interfaceName = interfaceInfo[@"name"] ?: @"未知";
    self.interfaceInfo = [interfaceInfo copy];
    
    // 2. 初始化PING配置（关键：memset清空结构体）
    cls_mtr_detector_config config;
    memset(&config, 0, sizeof(config)); // 必须初始化，避免残留值
    config.max_ttl = self.request.maxTTL;
    // 配置参数（timeout 已经是毫秒单位，直接使用）
    config.timeout_ms = self.request.timeout;
    config.times = self.request.maxTimes;
    config.prefer = self.request.prefer;  // 使用 request 中的 prefer 配置
    config.protocol = [self.request.protocol UTF8String];
    
    // 4. 处理网卡下标（unsigned int 类型适配，空值兜底）
    NSNumber *indexNum = interfaceInfo[@"index"];
    unsigned int interfaceIndex = 0;
    if (indexNum && [indexNum isKindOfClass:[NSNumber class]]) {
        NSInteger tempIndex = [indexNum integerValue];
        interfaceIndex = (tempIndex > 0) ? (unsigned int)tempIndex : 0;
    }
    config.interface_index = interfaceIndex;
    
    // 5. 执行PING检测（异常捕获，避免流程中断）
    cls_mtr_detector_result result;
    cls_mtr_detector_error_code code = cls_mtr_detector_error_unknown_error;
    @try {
        code = cls_mtr_detector_perform_mtr(domain, &config, &result);
    } @catch (NSException *exception) {
        NSLog(@"%@ 网卡%@（域名%@）：检测抛出异常：%@", kMtrLogPrefix, interfaceName, domainStr, exception);
        code = cls_mtr_detector_error_unknown_error;
    }
    
    // 6. 转换检测结果为JSON字符串
    char json_buffer[kMTRJsonBufferSize] = {0};
    cls_mtr_detector_result_to_json(&result,json_buffer, sizeof(json_buffer));
    
    // 7. 错误日志增强（补充上下文）
    if (code != cls_mtr_detector_error_success) {
        NSLog(@"%@ 网卡%@（域名%@）：检测失败，错误码：%d", kMtrLogPrefix, interfaceName, domainStr, code);
    }
    
    // 8. 解析JSON并构建上报数据
    NSString *jsonString = [[NSString alloc] initWithCString:json_buffer encoding:NSUTF8StringEncoding];
    NSLog(@"%@ 网卡%@（域名%@）：检测结果：%@", kMtrLogPrefix, interfaceName, domainStr, jsonString);
    NSDictionary *reportData = [self buildReportDataFromMtrResult:jsonString];
    
    // 9. 上报链路数据（语义化日志，避免冗余构建）
    // ✅ 创建 extraProvider 并传递接口名称
    CLSExtraProvider *extraProvider = [[CLSExtraProvider alloc] init];
    [extraProvider setExtra:@"network.interface.name" value:interfaceName ?: @""];
    
    CLSSpanBuilder *builder = [[CLSSpanBuilder builder] initWithName:@"network_diagnosis" provider:[[CLSSpanProviderDelegate alloc] initWithExtraProvider:extraProvider]];
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

#pragma mark - 公共接口
- (NSDictionary *)buildReportDataFromMtrResult:(NSString *)sectionResult {
    // 1. 空值校验
    if (!sectionResult || sectionResult.length == 0) {
        NSLog(@"%@ 上报数据：JSON字符串为空", kMtrLogPrefix);
        return @{};
    }
    
    // 2. JSON字符串转NSData（UTF-8编码，空值兜底）
    NSData *jsonData = [sectionResult dataUsingEncoding:NSUTF8StringEncoding];
    if (!jsonData) {
        NSLog(@"%@ 上报数据：JSON转Data失败，字符串：%@", kMtrLogPrefix, sectionResult);
        return @{};
    }
    
    // 3. 解析JSON为可变字典（带错误处理）
    NSError *parseError = nil;
    id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData
                                                    options:NSJSONReadingMutableContainers
                                                      error:&parseError];
    
    // 解析错误兜底
    if (parseError) {
        NSLog(@"%@ 上报数据：JSON解析失败：%@，原始字符串：%@", kMtrLogPrefix, parseError.localizedDescription, sectionResult);
        return @{};
    }
    
    // 4. 校验解析结果类型（必须是字典）
    if (![jsonObject isKindOfClass:[NSDictionary class]]) {
        NSLog(@"%@ 上报数据：JSON根节点非字典，实际类型：%@", kMtrLogPrefix, [jsonObject class]);
        return @{};
    }
    
    // 转换为可变字典（方便后续添加字段）
    // C 层已经将浮点数输出为字符串，避免了 IEEE 754 精度问题，这里无需格式化
    NSMutableDictionary *reportData = [NSMutableDictionary dictionaryWithDictionary:jsonObject];
    
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
    NSLog(@"%@ 上报数据：解析后的原始PING字典：%@", kMtrLogPrefix, reportData);
    return [reportData copy];
}

- (void)start:(CompleteCallback)complate{
    // 参数合法性校验
    NSError *validationError = nil;
    if (![CLSRequestValidator validateMtrRequest:self.request error:&validationError]) {
        NSLog(@"❌ MTR探测参数校验失败: %@", validationError.localizedDescription);
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
    
    NSLog(@"✅ MTR探测参数: maxTimes=%d, timeout=%dms, maxTTL=%d, protocol=%@, prefer=%d", 
          self.request.maxTimes, self.request.timeout, self.request.maxTTL, self.request.protocol, self.request.prefer);
    
    NSArray<NSDictionary *> *availableInterfaces = [CLSNetworkUtils getAvailableInterfacesForType];
    if (availableInterfaces.count == 0) {
        NSLog(@"%@ 无可用网卡接口", kMtrLogPrefix);
        CLSResponse *emptyResult = [CLSResponse complateResultWithContent:@{}];
        complate(emptyResult);
        return;
    }
    
    // 遍历网卡执行检测
    for (NSDictionary *interfaceInfo in availableInterfaces) {
        // ✅ 核心修复：为每个接口创建独立的探测对象，避免状态共享
        NSDictionary *capturedInterface = [interfaceInfo copy];
        CLSMultiInterfaceMtr *probeInstance = [[CLSMultiInterfaceMtr alloc] initWithRequest:self.request];
        probeInstance.topicId = self.topicId;
        probeInstance.networkAppId = self.networkAppId;
        probeInstance.appKey = self.appKey;
        probeInstance.uin = self.uin;
        probeInstance.region = self.region;
        probeInstance.endPoint = self.endPoint;
        
        NSString *interfaceName = capturedInterface[@"name"] ?: @"未知";
        NSLog(@"%@ 开始检测网卡：%@ (使用独立探测对象)", kMtrLogPrefix, interfaceName);
        [probeInstance startMtrWithCompletion:capturedInterface completion:complate];
        // 非多端口检测时，仅检测第一个网卡后退出
        if (self.request && !self.request.enableMultiplePortsDetect) {
            NSLog(@"%@ 非多端口检测模式，终止后续网卡检测", kMtrLogPrefix);
            break;
        }
    }
}

@end
