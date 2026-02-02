//
//  CLSDnsping.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/20.
//

#import <Foundation/Foundation.h>
#import "CLSDnsping.h"
#import "CLSRequestValidator.h"
#import "CLSNetworkUtils.h"
#import <netinet/in.h>
#import <sys/types.h>
#import <netinet/in.h>
#import <arpa/nameser.h>
#import <resolv.h>
#import <netdb.h>
#import <arpa/inet.h>
#import <sys/ioctl.h>
#import <net/if.h>
#import <sys/socket.h>
#import "CLSIdGenerator.h"
#import "CLSResponse.h"
#import "CLSSPanBuilder.h"
#import "CLSCocoa.h"
#import "CLSStringUtils.h"
#import "network_ios/cls_dns_detector.h"
#import "ClsNetworkDiagnosis.h"  // 引入以获取全局 userEx

// 常量定义
static NSString *const kDNSLogPrefix = @"[DNS检测]";
static NSString *const kDNSErrorDomain = @"CLSMultiInterfaceDns";

@interface CLSMultiInterfaceDns () <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>
@property (nonatomic, strong) NSDictionary *interfaceInfo;
@end

@implementation CLSMultiInterfaceDns

- (instancetype)initWithRequest:(CLSDnsRequest *)request {
    self = [super init];
    if (self) {
        _request = request;
    }
    return self;
}

#pragma mark - DNS服务器地址转换
- (const char **)convertNameServerToDnsServersArray {
    // 1. 空值校验：无自定义DNS时返回 {NULL} 数组
    if (!self.request || !self.request.nameServer || self.request.nameServer.length == 0) {
        const char **emptyArray = (const char **)malloc(sizeof(const char *) * 1);
        emptyArray[0] = NULL;
        return emptyArray;
    }
    
    // 2. 按逗号分割并清洗地址（去空格、过滤空值）
    NSArray<NSString *> *dnsServerList = [self.request.nameServer componentsSeparatedByString:@","];
    NSMutableArray<NSString *> *validServers = [NSMutableArray array];
    for (NSString *server in dnsServerList) {
        NSString *trimmedServer = [server stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmedServer.length > 0) {
            [validServers addObject:trimmedServer];
        }
    }
    
    // 3. 分配数组内存（元素数 + 1 用于NULL结尾）
    NSUInteger arrayCount = validServers.count + 1;
    const char **dnsServers = (const char **)malloc(sizeof(const char *) * arrayCount);
    if (!dnsServers) {
        NSLog(@"%@ 分配DNS服务器数组内存失败", kDNSLogPrefix);
        // 兜底返回空数组
        const char **emptyArray = (const char **)malloc(sizeof(const char *) * 1);
        emptyArray[0] = NULL;
        return emptyArray;
    }
    
    // 4. 填充数组（拷贝字符串到堆内存，避免野指针）
    for (NSUInteger i = 0; i < validServers.count; i++) {
        NSString *serverStr = validServers[i];
        const char *cStr = [serverStr UTF8String];
        char *heapStr = (char *)malloc(strlen(cStr) + 1);
        if (heapStr) {
            strcpy(heapStr, cStr);
            dnsServers[i] = heapStr;
        } else {
            NSLog(@"%@ 分配DNS地址字符串内存失败：%@", kDNSLogPrefix, serverStr);
            dnsServers[i] = NULL;
        }
    }
    
    // 5. 末尾添加NULL（符合底层接口要求）
    dnsServers[validServers.count] = NULL;
    
    return dnsServers;
}

- (void)freeDnsServersArray:(const char **)dnsServers {
    if (!dnsServers) return;
    
    // 遍历释放每个字符串内存，直到NULL
    for (int i = 0; dnsServers[i] != NULL; i++) {
        free((void *)dnsServers[i]);
    }
    free(dnsServers);
}

#pragma mark - 单网卡DNS检测
- (void)startDnsWithInterface:(NSDictionary *)interfaceInfo completion:(CompleteCallback)completion {
    // 空值校验
    if (!interfaceInfo) {
        NSLog(@"%@ 网卡信息为空，跳过检测", kDNSLogPrefix);
        CLSResponse *emptyResult = [CLSResponse complateResultWithContent:@{}];
        if (completion) completion(emptyResult);
        return;
    }
    
    self.interfaceInfo = [interfaceInfo copy];
    NSString *interfaceName = interfaceInfo[@"name"] ?: @"未知";
    
    // 1. 准备检测参数
    const char *domain = self.request ? [self.request.domain UTF8String] : NULL;
    if (!domain) {
        NSLog(@"%@ 网卡%@：检测域名为空", kDNSLogPrefix, interfaceName);
        CLSResponse *emptyResult = [CLSResponse complateResultWithContent:@{}];
        if (completion) completion(emptyResult);
        return;
    }
    
    const char **dnsServers = [self convertNameServerToDnsServersArray];
    char json_buffer[8192] = {0};
    
    // 2. 配置DNS检测参数
    cls_dns_detector_config config;
    memset(&config, 0, sizeof(config));
    config.dns_servers = dnsServers;
    // 配置参数（timeout 从秒转换为毫秒）
    config.timeout_ms = self.request ? (self.request.timeout * 1000) : 3000; // 默认超时3s
    config.prefer = self.request ? self.request.prefer : -1;  // 使用 request 中的 prefer 配置，默认自动检测
    
    // 处理网卡下标
    NSNumber *indexNum = interfaceInfo[@"index"];
    unsigned int interfaceIndex = 0;
    if (indexNum && [indexNum isKindOfClass:[NSNumber class]]) {
        NSInteger tempIndex = [indexNum integerValue];
        interfaceIndex = (tempIndex > 0) ? (unsigned int)tempIndex : 0;
    }
    config.interface_index = interfaceIndex;
    
    // 3. 执行DNS检测（保证内存释放）
    cls_dns_detector_result result;
    cls_dns_detector_error_code code = cls_dns_detector_error_unknown;
    @try {
        code = cls_dns_detector_perform_dns(domain, &config, &result);
    } @catch (NSException *exception) {
        NSLog(@"%@ 网卡%@：DNS检测异常：%@", kDNSLogPrefix, interfaceName, exception);
    } @finally {
        // 无论是否异常，都释放DNS服务器数组
        [self freeDnsServersArray:dnsServers];
    }
    
    // 4. 转换检测结果
    cls_dns_detector_result_to_json(&result, code, json_buffer, sizeof(json_buffer));
    if (code != cls_dns_detector_error_success) {
        NSLog(@"%@ 网卡%@：检测失败，错误码：%d", kDNSLogPrefix, interfaceName, code);
    }
    
    NSString *jsonString = [[NSString alloc] initWithCString:json_buffer encoding:NSUTF8StringEncoding];
    NSLog(@"%@ 网卡%@：检测结果：%@", kDNSLogPrefix, interfaceName, jsonString);
    
    // 5. 构建上报数据
    NSDictionary *reportData = [self buildReportDataFromDnsResult:jsonString];
    
    // 6. 上报链路数据并获取返回字典
    CLSSpanBuilder *builder = [[CLSSpanBuilder builder] initWithName:@"network_diagnosis" provider:[[CLSSpanProviderDelegate alloc] init]];
    [builder setURL:self.request.domain];
    [builder setpageName:self.request.pageName];
    // 设置自定义traceId
    if (self.request.traceId) {
        [builder setTraceId:self.request.traceId];
    }
    NSDictionary *d = [builder report:self.topicId reportData:reportData];
    
    // 7. 构建响应并回调
    CLSResponse *callbackResult = [CLSResponse complateResultWithContent:d ?: @{}];
    if (completion) {
        completion(callbackResult);
    }
}

#pragma mark - 构建上报数据
- (NSDictionary *)buildReportDataFromDnsResult:(NSString *)sectionResult {
    // 1. 空值校验
    if (!sectionResult || sectionResult.length == 0) {
        NSLog(@"%@ 上报数据：JSON字符串为空", kDNSLogPrefix);
        return @{};
    }
    
    // 2. JSON转Data
    NSData *jsonData = [sectionResult dataUsingEncoding:NSUTF8StringEncoding];
    if (!jsonData) {
        NSLog(@"%@ 上报数据：JSON转Data失败，字符串：%@", kDNSLogPrefix, sectionResult);
        return @{};
    }
    
    // 3. 解析JSON
    NSError *parseError = nil;
    id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData
                                                    options:NSJSONReadingMutableContainers
                                                      error:&parseError];
    if (parseError) {
        NSLog(@"%@ 上报数据：JSON解析失败：%@，原始字符串：%@", kDNSLogPrefix, parseError.localizedDescription, sectionResult);
        return @{};
    }
    
    // 4. 校验解析结果类型
    if (![jsonObject isKindOfClass:[NSMutableDictionary class]]) {
        NSLog(@"%@ 上报数据：JSON根节点非字典，实际类型：%@", kDNSLogPrefix, [jsonObject class]);
        return @{};
    }
    
    NSMutableDictionary *reportData = (NSMutableDictionary *)jsonObject;
    NSLog(@"%@ 上报数据：解析后的原始字典：%@", kDNSLogPrefix, reportData);
    
    // 5. 追加通用字段（空值兜底）
    reportData[@"appKey"] = self.request.appKey;
    reportData[@"src"] = @"app";
    // 优先使用request中的traceId，如果没有则自动生成
    reportData[@"trace_id"] = self.request.traceId ?: CLSIdGenerator.generateTraceId ?: @"";
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

#pragma mark - 启动多网卡DNS检测
- (void)start:(CompleteCallback)completion {
    // 参数合法性校验
    NSError *validationError = nil;
    if (![CLSRequestValidator validateDnsRequest:self.request error:&validationError]) {
        NSLog(@"❌ DNS探测参数校验失败: %@", validationError.localizedDescription);
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
    
    NSLog(@"✅ DNS探测参数: maxTimes=%d, timeout=%ds, prefer=%d", 
          self.request.maxTimes, self.request.timeout, self.request.prefer);
    
    NSArray<NSDictionary *> *availableInterfaces = [CLSNetworkUtils getAvailableInterfacesForType];
    if (availableInterfaces.count == 0) {
        NSLog(@"%@ 无可用网卡接口", kDNSLogPrefix);
        CLSResponse *emptyResult = [CLSResponse complateResultWithContent:@{}];
        if (completion) completion(emptyResult);
        return;
    }
    
    // 遍历网卡执行检测（参考 Ping/MTR：支持 enableMultiplePortsDetect 控制）
    for (NSDictionary *interfaceInfo in availableInterfaces) {
        NSString *interfaceName = interfaceInfo[@"name"] ?: @"未知";
        NSLog(@"%@ 开始检测网卡：%@", kDNSLogPrefix, interfaceName);
        [self startDnsWithInterface:interfaceInfo completion:completion];
        
        // 非多端口检测时，仅检测第一个网卡后退出
        if (self.request && !self.request.enableMultiplePortsDetect) {
            NSLog(@"%@ 非多端口检测模式，终止后续网卡检测", kDNSLogPrefix);
            break;
        }
    }
}

@end
