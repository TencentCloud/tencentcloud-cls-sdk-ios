//
//  CLSNetworkDiagnosisBaseTests.m
//  TencentCloudLogDemoTests
//
//  Created by AI Assistant on 2026/01/04.
//

#import "CLSNetworkDiagnosisBaseTests.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>

@implementation CLSNetworkDiagnosisBaseTests

- (void)setUp {
    [super setUp];
    
    // ⚙️ 配置 CLS 日志上报
    
    // ⚙️ 配置网络探测实例
    //
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:kLiveEndpoint
                                                       accessKeyId:@""
                                                         accessKey:@""];
    self.diagnosis = [ClsNetworkDiagnosis sharedInstance];
    [[ClsNetworkDiagnosis sharedInstance] setupLogSenderWithConfig:config netToken:kLiveNetToken];
    [self.diagnosis setUserEx:@{@"cls_sdk_test": @"!@#$%^&*()_+-=[]{}|;:\'\",.<>/?", @"cls_sdk_test2": @"!@#$%^&*()_+-=[]{}|;:\'\",.<>/?",@"业务": @"日志服务"}];

}

- (void)tearDown {
    self.diagnosis = nil;
    [super tearDown];
}

#pragma mark - 工具方法

- (NSDictionary *)parseResponseContent:(CLSResponse *)response {
    if (!response || !response.content) {
        XCTFail(@"响应对象为空或content字段缺失");
        return @{};
    }
    
    NSError *error;
    NSDictionary *dict = [self dictionaryFromString:response.content error:&error];
    if (error) {
        XCTFail(@"JSON 解析失败: %@，原始内容：%@", error.localizedDescription, response.content);
        return @{};
    }
    return dict;
}

- (NSDictionary *)safeConvertToDictionary:(id)rawValue {
    if (!rawValue || [rawValue isKindOfClass:[NSNull class]]) {
        return @{};
    }
    if ([rawValue isKindOfClass:[NSDictionary class]]) {
        return (NSDictionary *)rawValue;
    }
    if ([rawValue isKindOfClass:[NSString class]]) {
        NSError *error;
        NSDictionary *dict = [self dictionaryFromString:(NSString *)rawValue error:&error];
        return dict ?: @{};
    }
    return @{};
}

- (NSArray *)safeConvertToArray:(id)rawValue {
    if (!rawValue || [rawValue isKindOfClass:[NSNull class]]) {
        return @[];
    }
    if ([rawValue isKindOfClass:[NSArray class]]) {
        return (NSArray *)rawValue;
    }
    return @[];
}

- (NSDictionary *)dictionaryFromString:(NSString *)string error:(NSError **)error {
    if (!string || string.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"CLSTestErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"输入字符串为空"}];
        return @{};
    }
    NSData *jsonData = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (!jsonData) {
        if (error) *error = [NSError errorWithDomain:@"CLSTestErrorDomain" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"字符串转Data失败"}];
        return @{};
    }
    id result = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
    if ([result isKindOfClass:[NSDictionary class]]) {
        return (NSDictionary *)result;
    }
    return @{};
}

#pragma mark - 公共字段校验

- (void)validateCommonFields:(NSDictionary *)data {
    NSParameterAssert(data);
    NSLog(@"📋 验证公共字段...");
    
    // 公共字段: name, traceID, start, duration, end, service
    NSArray *commonKeys = @[@"name", @"traceID", @"start", @"duration", @"end"];
    for (NSString *key in commonKeys) {
        [self validateNonNilValueInDict:data key:key failureMessage:[NSString stringWithFormat:@"缺失公共字段: %@", key]];
    }
    
    // name 应为 network_diagnosis
    XCTAssertEqualObjects(data[@"name"], @"network_diagnosis", @"name应为network_diagnosis");
    
    // 时间戳校验（纳秒级）
    long long start = [data[@"start"] longLongValue];
    long long duration = [data[@"duration"] longLongValue];
    long long end = [data[@"end"] longLongValue];
    
    XCTAssertGreaterThan(start, kMinNanoTimestamp, @"start 应为纳秒时间戳");
    XCTAssertEqual(end - start, duration, @"end - start 应等于 duration");
    XCTAssertGreaterThanOrEqual(duration, 0, @"duration 应为非负数");
    NSLog(@"   ✅ 公共字段验证通过");
}

- (void)validateResourceFields:(NSDictionary *)data {
    NSLog(@"📋 验证Resource字段...");
    NSDictionary *resource = [self safeConvertToDictionary:data[@"resource"]];
    XCTAssertNotNil(resource, @"缺失 resource 字段");
    
    // Resource 必需字段（根据规范）
    NSArray *requiredKeys = @[
        @"app.name", @"app.version", @"app.versionCode",
        @"device.brand", @"device.model.name", @"device.model.identifier",
        @"host.arch", @"host.name",
        @"os.name", @"os.version", @"os.type",
        @"net.access",
        @"sdk.language", @"cls.sdk.version"
    ];
    for (NSString *key in requiredKeys) {
        [self validateNonNilValueInDict:resource key:key failureMessage:[NSString stringWithFormat:@"缺失 resource 字段: %@", key]];
    }
    
    // 验证 carrier 字段（iOS 16.4+ 运营商信息可能为占位符）
    [self validateCarrierField:resource];
    
    NSLog(@"   ✅ Resource字段验证通过");
}

/// 验证运营商字段不是占位符
/// iOS 16.4+ 系统可能返回空值或占位符，SDK应将其替换为 "IOS"
- (void)validateCarrierField:(NSDictionary *)resource {
    NSString *carrier = resource[@"carrier"];
    NSLog(@"📱 验证carrier字段: [%@]", carrier ?: @"(nil)");
    
    // carrier 字段应该存在
    XCTAssertNotNil(carrier, @"缺失 carrier 字段");
    
    // carrier 不应为空字符串
    XCTAssertGreaterThan(carrier.length, 0, @"carrier 不应为空字符串");
    
    NSString *trimmed = [carrier stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // 定义无效的占位符列表
    NSArray *invalidPlaceholders = @[
        @"-", @"--", @"---",
        @"Unknown", @"unknown",
        @"无运营商",
        @"占位符",
        @"placeholder", @"Placeholder",
        @"Carrier", @"carrier",
        @"null", @"nil", @"n/a", @"N/A"
    ];
    
    // 验证 carrier 不是占位符
    for (NSString *placeholder in invalidPlaceholders) {
        XCTAssertFalse([trimmed caseInsensitiveCompare:placeholder] == NSOrderedSame,
                      @"carrier 不应为占位符 '%@'，iOS 16.4+ 应填充为 'IOS'，实际值: '%@'", placeholder, carrier);
    }
    
    // 验证 carrier 长度大于1（单字符通常是无效占位符）
    XCTAssertGreaterThan(trimmed.length, 1,
                        @"carrier 长度应大于1（单字符通常是占位符），iOS 16.4+ 应填充为 'IOS'，实际值: '%@'", carrier);
    
    NSLog(@"   ✅ carrier字段验证通过: %@", carrier);
}

- (void)validateAttributeFields:(NSDictionary *)data expectedType:(NSString *)type {
    NSLog(@"📋 验证Attribute字段...");
    NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
    XCTAssertNotNil(attribute, @"缺失 attribute 字段");
    XCTAssertEqualObjects(attribute[@"net.type"], type, @"net.type 应为 %@", type);
    // page.name 可以为 null，不做强制校验
    NSLog(@"   ✅ Attribute字段验证通过 (net.type=%@)", type);
}

- (void)validateNetOriginFields:(NSDictionary *)data expectedMethod:(NSString *)method {
    NSLog(@"📋 验证net.origin基础字段...");
    NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
    NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
    XCTAssertNotNil(origin, @"缺失 net.origin 字段");
    
    // 公共必需字段
    XCTAssertEqualObjects(origin[@"method"], method, @"method 应为 %@", method);
    XCTAssertNotNil(origin[@"trace_id"], @"缺失 trace_id 字段");
    XCTAssertNotNil(origin[@"appKey"], @"缺失 appKey 字段");
    XCTAssertEqualObjects(origin[@"src"], @"app", @"src 应为 app");
    
    NSLog(@"   ✅ net.origin基础字段验证通过");
}

- (void)validateNetInfo:(NSDictionary *)netInfo {
    NSLog(@"📋 验证netInfo字段...");
    XCTAssertNotNil(netInfo, @"缺失 netInfo 字段");
    
    NSArray *netInfoKeys = @[@"dns", @"defaultNet", @"usedNet", @"client_ip", @"country_id", @"isp_en", @"province_en", @"city_en", @"country_en"];
    for (NSString *key in netInfoKeys) {
        [self validateNonNilValueInDict:netInfo key:key failureMessage:[NSString stringWithFormat:@"缺失: netInfo.%@", key]];
    }
    NSLog(@"   ✅ netInfo字段验证通过");
}

- (void)validateExtensionFields:(NSDictionary *)data
               expectedDetectEx:(NSDictionary *)expectedDetectEx {
    NSLog(@"📋 验证扩展字段...");
    
    // detectEx: 业务扩展字段
    if (expectedDetectEx) {
        NSDictionary *detectEx = [self safeConvertToDictionary:data[@"detectEx"]];
        XCTAssertNotNil(detectEx, @"缺失 detectEx 字段");
        for (NSString *key in expectedDetectEx) {
            XCTAssertEqualObjects(detectEx[key], expectedDetectEx[key], @"detectEx.%@ 值不匹配", key);
        }
    }
    
    NSLog(@"   ✅ 扩展字段验证通过");
}

- (void)validateUserExFields:(NSDictionary *)data
              expectedUserEx:(NSDictionary *)expectedUserEx {
    NSLog(@"📋 验证 userEx 全局字段...");
    
    NSDictionary *userEx = [self safeConvertToDictionary:data[@"userEx"]];
    XCTAssertNotNil(userEx, @"缺失 userEx 字段");
    
    if (expectedUserEx) {
        for (NSString *key in expectedUserEx) {
            XCTAssertEqualObjects(userEx[key], expectedUserEx[key], @"userEx.%@ 值不匹配，期望: %@，实际: %@", key, expectedUserEx[key], userEx[key]);
        }
        NSLog(@"   ✅ userEx 全局字段验证通过: %@", userEx);
    } else {
        // 验证默认设置的 userEx
        NSDictionary *globalUserEx = [[ClsNetworkDiagnosis sharedInstance] getUserEx];
        for (NSString *key in globalUserEx) {
            XCTAssertEqualObjects(userEx[key], globalUserEx[key], @"userEx.%@ 值不匹配，期望: %@，实际: %@", key, globalUserEx[key], userEx[key]);
        }
        NSLog(@"   ✅ userEx 全局字段验证通过（使用全局默认值）: %@", userEx);
    }
}

- (void)validateNonNilValueInDict:(NSDictionary *)dict key:(NSString *)key failureMessage:(NSString *)message {
    if (!dict) {
        XCTFail(@"字典为空，无法验证 key: %@", key);
        return;
    }
    id value = dict[key];
    XCTAssertTrue(value != nil && ![value isKindOfClass:[NSNull class]], @"%@", message);
}

#pragma mark - Ping 专项校验

- (void)validatePingOriginFields:(NSDictionary *)origin {
    NSLog(@"📋 验证Ping专用字段...");
    
    // Ping 必需字段（根据规范）
    NSArray *requiredKeys = @[@"host", @"host_ip", @"interface", @"count", @"size", @"total", @"loss",
                               @"latency_min", @"latency_max", @"latency", @"stddev",
                               @"responseNum", @"exceptionNum", @"bindFailed"];
    for (NSString *key in requiredKeys) {
        [self validateNonNilValueInDict:origin key:key failureMessage:[NSString stringWithFormat:@"Ping缺失字段: %@", key]];
    }
    NSLog(@"   ✅ Ping专用字段验证通过");
}

- (void)validatePingStatisticsFields:(NSDictionary *)origin expectedCount:(NSInteger)count expectedSize:(NSInteger)size {
    NSLog(@"📋 验证Ping统计字段...");
    
    if (count > 0) {
        XCTAssertEqual([origin[@"count"] integerValue], count, @"探测次数应为 %ld", (long)count);
    }
    if (size > 0) {
        XCTAssertEqual([origin[@"size"] integerValue], size, @"包大小应为 %ld", (long)size);
    }
    
    // 延迟字段逻辑校验
    double latency_min = [origin[@"latency_min"] doubleValue];
    double latency_max = [origin[@"latency_max"] doubleValue];
    double latency_avg = [origin[@"latency"] doubleValue];
    
    if (latency_min > 0 && latency_max > 0) {
        XCTAssertLessThanOrEqual(latency_min, latency_avg, @"最小延迟应 <= 平均延迟");
        XCTAssertGreaterThanOrEqual(latency_max, latency_avg, @"最大延迟应 >= 平均延迟");
    }
    NSLog(@"   ✅ Ping统计字段验证通过");
}

#pragma mark - TCPPing 专项校验

- (void)validateTcppingOriginFields:(NSDictionary *)origin expectedPort:(NSInteger)port {
    NSLog(@"📋 验证TCPPing专用字段...");
    
    // TCPPing 必需字段（根据规范）
    NSArray *requiredKeys = @[@"host", @"host_ip", @"port", @"interface", @"count", @"total", @"loss",
                               @"latency_min", @"latency_max", @"latency", @"stddev",
                               @"responseNum", @"exceptionNum", @"bindFailed"];
    for (NSString *key in requiredKeys) {
        [self validateNonNilValueInDict:origin key:key failureMessage:[NSString stringWithFormat:@"TCPPing缺失字段: %@", key]];
    }
    
    if (port > 0) {
        XCTAssertEqual([origin[@"port"] integerValue], port, @"端口应为 %ld", (long)port);
    }
    NSLog(@"   ✅ TCPPing专用字段验证通过");
}

- (void)validateTcppingStatisticsFields:(NSDictionary *)origin expectedCount:(NSInteger)count {
    NSLog(@"📋 验证TCPPing统计字段...");
    
    if (count > 0) {
        XCTAssertEqual([origin[@"count"] integerValue], count, @"探测次数应为 %ld", (long)count);
    }
    
    // 延迟字段逻辑校验
    double latency_min = [origin[@"latency_min"] doubleValue];
    double latency_max = [origin[@"latency_max"] doubleValue];
    double latency_avg = [origin[@"latency"] doubleValue];
    
    if (latency_min > 0 && latency_max > 0) {
        XCTAssertLessThanOrEqual(latency_min, latency_avg, @"最小延迟应 <= 平均延迟");
        XCTAssertGreaterThanOrEqual(latency_max, latency_avg, @"最大延迟应 >= 平均延迟");
    }
    NSLog(@"   ✅ TCPPing统计字段验证通过");
}

#pragma mark - DNS 专项校验

- (void)validateDnsOriginFields:(NSDictionary *)origin {
    NSLog(@"📋 验证DNS专用字段...");
    
    // DNS 必需字段（根据规范）
    NSArray *requiredKeys = @[@"domain", @"status", @"id", @"flags", @"latency", @"host_ip",
                               @"QUESTION_SECTION", @"QUERY", @"ANSWER", @"AUTHORITY", @"ADDITIONAL"];
    for (NSString *key in requiredKeys) {
        [self validateNonNilValueInDict:origin key:key failureMessage:[NSString stringWithFormat:@"DNS缺失字段: %@", key]];
    }
    NSLog(@"   ✅ DNS专用字段验证通过");
}

- (void)validateDnsAnswerFields:(NSDictionary *)origin {
    NSLog(@"📋 验证DNS解析结果...");
    
    NSString *status = origin[@"status"];
    XCTAssertNotNil(status, @"status不应为空");
    
    if ([status isEqualToString:@"NOERROR"]) {
        // 正常解析时应该有ANSWER_SECTION
        NSArray *answers = [self safeConvertToArray:origin[@"ANSWER_SECTION"]];
        XCTAssertGreaterThan(answers.count, 0, @"NOERROR状态下ANSWER_SECTION不应为空");
        
        // 检查每条记录的字段
        for (NSDictionary *answer in answers) {
            if ([answer isKindOfClass:[NSDictionary class]]) {
                XCTAssertNotNil(answer[@"name"], @"DNS记录应包含name");
                // atype 或 type
                XCTAssertTrue(answer[@"atype"] != nil || answer[@"type"] != nil, @"DNS记录应包含atype或type");
            }
        }
    }
    NSLog(@"   ✅ DNS解析结果验证通过");
}

#pragma mark - HTTP 专项校验

- (void)validateHttpOriginFields:(NSDictionary *)origin {
    NSLog(@"📋 验证HTTP专用字段...");
    
    // HTTP 必需字段（根据规范）
    NSArray *requiredKeys = @[@"url", @"host_ip", @"domain", @"remoteAddr",
                               @"dnsTime", @"tcpTime", @"sslTime", @"firstByteTime", @"allByteTime", @"requestTime",
                               @"httpCode", @"httpProtocol", @"sendBytes", @"receiveBytes"];
    for (NSString *key in requiredKeys) {
        [self validateNonNilValueInDict:origin key:key failureMessage:[NSString stringWithFormat:@"HTTP缺失字段: %@", key]];
    }
    NSLog(@"   ✅ HTTP专用字段验证通过");
}

- (void)validateHttpTimeFields:(NSDictionary *)origin {
    NSLog(@"📋 验证HTTP时间字段...");
    
    // 时间字段应为非负数
    NSArray *timeFields = @[@"waitDnsTime", @"dnsTime", @"tcpTime", @"sslTime", @"firstByteTime", @"allByteTime", @"requestTime"];
    for (NSString *field in timeFields) {
        id value = origin[field];
        if (value && ![value isKindOfClass:[NSNull class]]) {
            double timeValue = [value doubleValue];
            XCTAssertGreaterThanOrEqual(timeValue, 0, @"%@ 应为非负数", field);
        }
    }
    NSLog(@"   ✅ HTTP时间字段验证通过");
}

- (void)validateHttpHeadersFields:(NSDictionary *)data {
    NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
    NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
    NSDictionary *headers = [self safeConvertToDictionary:origin[@"headers"]];
    XCTAssertNotNil(headers, @"缺失 headers 字段");
    NSLog(@"   ✅ HTTP headers字段验证通过");
}

- (void)validateHttpDescFields:(NSDictionary *)data {
    NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
    NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
    NSDictionary *desc = [self safeConvertToDictionary:origin[@"desc"]];
    XCTAssertNotNil(desc, @"缺失 desc 字段");
    [self validateHttpDescTimeSequence:desc];
    NSLog(@"   ✅ HTTP desc字段验证通过");
}

- (void)validateHttpDescTimeSequence:(NSDictionary *)desc {
    // HTTP 请求生命周期时间点（根据规范）
    NSArray *timeFields = @[
        @"callStart", @"dnsStart", @"dnsEnd", @"connectStart",
        @"secureConnectStart", @"secureConnectEnd", @"connectionAcquired",
        @"requestHeaderStart", @"requestHeaderEnd",
        @"responseHeadersStart", @"responseHeaderEnd",
        @"responseBodyStart", @"responseBodyEnd",
        @"connectionReleased", @"callEnd"
    ];
    for (NSString *field in timeFields) {
        [self validateNonNilValueInDict:desc key:field failureMessage:[NSString stringWithFormat:@"缺失: desc.%@", field]];
    }
}

#pragma mark - MTR 专项校验

- (void)validateMtrOriginFields:(NSDictionary *)origin {
    NSLog(@"📋 验证MTR专用字段...");
    
    // MTR 必需字段（根据规范）
    NSArray *requiredKeys = @[@"host", @"type", @"max_paths", @"paths"];
    for (NSString *key in requiredKeys) {
        [self validateNonNilValueInDict:origin key:key failureMessage:[NSString stringWithFormat:@"MTR缺失字段: %@", key]];
    }
    NSLog(@"   ✅ MTR专用字段验证通过");
}

- (void)validateMtrPathsFields:(NSArray *)paths expectedProtocol:(NSString *)protocol {
    NSLog(@"📋 验证MTR paths数组...");
    XCTAssertGreaterThan(paths.count, 0, @"paths 数组不应为空");
    
    for (NSDictionary *path in paths) {
        if (![path isKindOfClass:[NSDictionary class]]) continue;
        
        // path 必需字段（根据规范）
        NSArray *pathKeys = @[@"host", @"host_ip", @"type", @"path", @"lastHop", @"timestamp",
                               @"interface", @"protocol", @"exceptionNum", @"bindFailed", @"result"];
        for (NSString *key in pathKeys) {
            [self validateNonNilValueInDict:path key:key failureMessage:[NSString stringWithFormat:@"MTR path缺失字段: %@", key]];
        }
        
        // 验证协议
        if (protocol) {
            XCTAssertEqualObjects([path[@"protocol"] lowercaseString], [protocol lowercaseString], @"protocol应为 %@", protocol);
        }
        
        // 验证 result (hops) 数组
        NSArray *hops = [self safeConvertToArray:path[@"result"]];
        for (NSDictionary *hop in hops) {
            if ([hop isKindOfClass:[NSDictionary class]]) {
                [self validateMtrHopFields:hop];
            }
        }
    }
    NSLog(@"   ✅ MTR paths数组验证通过");
}

- (void)validateMtrHopFields:(NSDictionary *)hop {
    // 每一跳的必需字段（根据规范）
    NSArray *hopKeys = @[@"hop", @"ip", @"loss", @"latency_min", @"latency_max", @"latency", @"responseNum", @"stddev"];
    for (NSString *key in hopKeys) {
        [self validateNonNilValueInDict:hop key:key failureMessage:[NSString stringWithFormat:@"MTR hop缺失字段: %@", key]];
    }
}

#pragma mark - IP地址校验

- (BOOL)isIPv4Address:(NSString *)address {
    if (address.length == 0) return NO;
    
    NSString *ipv4Pattern = @"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$";
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", ipv4Pattern];
    return [predicate evaluateWithObject:address];
}

- (BOOL)isIPv6Address:(NSString *)address {
    if (address.length == 0) return NO;
    return [address containsString:@":"] && ![self isIPv4Address:address];
}

#pragma mark - 环境可达性探测

- (BOOL)isPublicIPv6Reachable {
    int sock = socket(AF_INET6, SOCK_DGRAM, 0);
    if (sock < 0) return NO;
    struct sockaddr_in6 addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin6_family = AF_INET6;
    addr.sin6_port = htons(53);
    inet_pton(AF_INET6, "2001:4860:4860::8888", &addr.sin6_addr);
    int rc = connect(sock, (struct sockaddr *)&addr, sizeof(addr));
    close(sock);
    return rc == 0;
}

#pragma mark - 日志方法

- (void)logKeyResult:(NSDictionary *)data withTitle:(NSString *)title {
    NSLog(@"🔍 ===== %@ =====", title);
    NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
    NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
    NSLog(@"📋 关键信息: method=%@, host=%@, traceID=%@", origin[@"method"], origin[@"host"] ?: origin[@"domain"], data[@"traceID"]);
}

- (void)logCompleteResult:(NSDictionary *)data withTitle:(NSString *)title {
    NSLog(@"🔍 ========== %@ ==========", title);
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:&error];
    if (!error && jsonData) {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        
        // 分段打印以防止控制台截断
        NSUInteger length = jsonString.length;
        NSUInteger chunkSize = 800;
        for (NSUInteger i = 0; i < length; i += chunkSize) {
            NSUInteger remaining = length - i;
            NSUInteger currentChunkSize = (remaining > chunkSize) ? chunkSize : remaining;
            NSString *chunk = [jsonString substringWithRange:NSMakeRange(i, currentChunkSize)];
            if (i == 0) {
                NSLog(@"📄 完整JSON: %@", chunk);
            } else {
                NSLog(@"📄 (继续): %@", chunk);
            }
        }
    }
}

@end

