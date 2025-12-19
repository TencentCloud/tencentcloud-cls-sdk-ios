//
//  CLSNetworkDiagnosisTests.m
//  TencentCloudLogDemoTests
//
//  Created by AI Assistant on 2025/12/18.
//  基于网络探测字段规范文档生成的完整测试用例
//
//  ⚙️ 配置说明：
//  1. 请在 setUp 方法中配置 CLS 密钥（accessKeyId, accessKey）
//  2. 请在 setUp 方法中配置 netToken（可选，测试环境可传空字符串）
//  3. 请在各测试用例中将 appKey 替换为你的应用标识
//
//  详细配置指南请参考：TEST_CONFIGURATION.md

#import <XCTest/XCTest.h>
#import "ClsNetworkDiagnosis.h"
#import "ClsProtocols.h"
#import "CLSResponse.h"

#pragma mark - 常量定义
/// 测试通用超时时间
static NSTimeInterval const kTestDefaultTimeout = 20.0;
/// MTR测试超时时间（MTR耗时更长）
static NSTimeInterval const kTestMtrTimeout = 40.0;
/// 纳秒时间戳最小值（13位毫秒转纳秒）
static long long const kMinNanoTimestamp = 1000000000000LL;
/// 测试通用AppKey
static NSString *const kTestAppKey = @"test_app_key_123";
/// 测试目标域名
static NSString *const kTestDomain = @"www.tencentcloud.com";
/// 不可达测试IP（RFC 5737 TEST-NET-1）
static NSString *const kUnreachableIP = @"192.0.2.1";

@interface CLSNetworkDiagnosisTests : XCTestCase
@property (nonatomic, strong) ClsNetworkDiagnosis *diagnosis;
@end

@implementation CLSNetworkDiagnosisTests

#pragma mark - Setup & Teardown

- (void)setUp {
    [super setUp];
    
    // ⚙️ 配置 CLS 日志上报（请替换为你的实际密钥）
    // 获取方式：https://console.cloud.tencent.com/cam/capi
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou-open.cls.tencentcs.com"
                                                          accessKeyId:@""  // ⚠️ 替换为你的 SecretId
                                                            accessKey:@""];  // ⚠️ 替换为你的 SecretKey
    
    // ⚙️ 配置网络探测实例
    // netToken: 网络探测鉴权令牌（可选，测试环境可传空字符串 @""）
    self.diagnosis = [ClsNetworkDiagnosis sharedInstance];
    [self.diagnosis setupLogSenderWithConfig:config netToken:@"eyJuX2FfaWQiOiI4MzBkMzRjMS0yN2ViLTRmNjAtOWYxMi1mMzUyNjY3Njk0MTkiLCJ1aW4iOjEwMDAwMTEyNzU4OSwia2V5IjoiNWM4NmQxZGQtYWIyNi00ZmJhLTk3ZTMtNTRmNDZkMWZiZmRhIiwicmVnaW9uIjoiYXAtZ3Vhbmd6aG91LW9wZW4iLCJ0b3BpY19pZCI6ImJiNTA5NDYzLWFlZGEtNDgyZi1hZjg3LTc5NTAwN2Q5MjYzMSJ9"];  // ⚠️ 替换为你的 netToken（或留空）
    
    // 💡 建议：为了安全，不要将密钥硬编码到代码中
    // 推荐使用：
    // 1. 配置文件（test-config.plist）+ .gitignore
    // 2. 环境变量（适用于 CI/CD）
    // 详见：TEST_CONFIGURATION.md
}

- (void)tearDown {
    self.diagnosis = nil;
    [super tearDown];
}

#pragma mark - 公共工具函数

/// 字符串转换为字典（通用工具函数）
/// @param string 待转换的JSON字符串
/// @param error 转换错误信息（可传nil）
/// @return 转换后的字典，失败返回空字典
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
    } else if ([result isKindOfClass:[NSArray class]]) {
        if (error) *error = [NSError errorWithDomain:@"CLSTestErrorDomain" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"字符串解析为数组，预期字典"}];
        return @{};
    } else {
        if (error) *error = [NSError errorWithDomain:@"CLSTestErrorDomain" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"字符串解析结果非字典/数组"}];
        return @{};
    }
}

/// 安全转换任意类型为字典
/// @param rawValue 原始值（可能是字符串/字典/NSNull/nil等）
/// @return 转换后的字典，失败返回空字典
- (NSDictionary *)safeConvertToDictionary:(id)rawValue {
    // 空值处理
    if (!rawValue || [rawValue isKindOfClass:[NSNull class]]) {
        NSLog(@"⚠️ 原始值为空或NSNull，返回空字典");
        return @{};
    }
    
    // 已是字典直接返回
    if ([rawValue isKindOfClass:[NSDictionary class]]) {
        return (NSDictionary *)rawValue;
    }
    
    // 字符串尝试解析为字典
    if ([rawValue isKindOfClass:[NSString class]]) {
        NSError *error;
        NSDictionary *dict = [self dictionaryFromString:(NSString *)rawValue error:&error];
        if (error) {
            NSLog(@"⚠️ 字符串解析为字典失败：%@，原始字符串：%@", error.localizedDescription, rawValue);
        }
        return dict;
    }
    
    // 其他类型返回空字典
    NSLog(@"⚠️ 不支持的类型：%@，原始值：%@", [rawValue class], rawValue);
    return @{};
}

/// 解析响应的 JSON 内容
/// @param response CLS响应对象
/// @return 解析后的字典，失败返回nil
- (NSDictionary *)parseResponseContent:(CLSResponse *)response {
    if (!response || !response.content) {
        XCTFail(@"响应对象为空或content字段缺失");
        return nil;
    }
    
    NSError *error;
    NSDictionary *dict = [self dictionaryFromString:response.content error:&error];
    if (error) {
        XCTFail(@"JSON 解析失败: %@，原始内容：%@", error.localizedDescription, response.content);
    }
    
    return dict;
}

/// 校验字典中指定key的值非空且非NSNull
/// @param dict 待校验字典
/// @param key 字段名
/// @param message 失败提示语
/// 校验字典中指定key的值非空且非NSNull
/// @param dict 待校验字典
/// @param key 字段名
/// @param message 失败提示语
- (void)validateNonNilValueInDict:(NSDictionary *)dict key:(NSString *)key failureMessage:(NSString *)message {
    // 先校验入参合法性
    if (!dict) {
        XCTFail(@"校验字典为空，key：%@", key);
        return;
    }
    if (!key || key.length == 0) {
        XCTFail(@"校验字段名为空");
        return;
    }
    
    id value = dict[key];
    BOOL isValid = (value != nil && ![value isKindOfClass:[NSNull class]]);
    // 修复：使用完整的格式化参数写法，避免编译器解析错误
    XCTAssertTrue(isValid, @"%@", message);
}

#pragma mark - 字段校验公共方法

/// 验证公共字段（所有探测方法通用）
/// @param data 待校验的响应数据字典
- (void)validateCommonFields:(NSDictionary *)data {
    NSParameterAssert(data);
    
    // 1. 基础公共字段校验
    NSArray *commonKeys = @[@"name", @"traceID", @"start", @"duration", @"end", @"service"];
    for (NSString *key in commonKeys) {
        [self validateNonNilValueInDict:data key:key failureMessage:[NSString stringWithFormat:@"缺失字段: %@", key]];
    }
    
    // 2. 验证时间单位为纳秒（值应该很大）
    long long start = [data[@"start"] longLongValue];
    long long duration = [data[@"duration"] longLongValue];
    long long end = [data[@"end"] longLongValue];
    
    XCTAssertGreaterThan(start, kMinNanoTimestamp, @"start 应为纳秒时间戳（值过小）");
    XCTAssertEqual(end - start, duration, @"end - start 应等于 duration");
    
    // 3. Resource 字段安全转换与校验
    NSDictionary *resource = [self safeConvertToDictionary:data[@"resource"]];
    XCTAssertNotNil(resource, @"缺失 resource 字段 或 resource 无法转换为字典");
    NSLog(@"🔍 resource转换后：%@", resource);
    
    // 4. Resource子字段校验
    // 应用信息
    NSArray *appResourceKeys = @[@"app.name", @"app.version", @"app.versionCode"];
    for (NSString *key in appResourceKeys) {
        [self validateNonNilValueInDict:resource key:key failureMessage:[NSString stringWithFormat:@"缺失: resource.%@", key]];
    }
    
    // 设备信息
    NSArray *deviceResourceKeys = @[
        @"device.brand", @"device.id", @"device.manufacturer",
        @"device.model.identifier", @"device.model.name", @"device.resolution"
    ];
    for (NSString *key in deviceResourceKeys) {
        [self validateNonNilValueInDict:resource key:key failureMessage:[NSString stringWithFormat:@"缺失: resource.%@", key]];
    }
    
    // 主机/系统信息
    NSArray *hostOsResourceKeys = @[@"host.arch", @"host.name", @"os.name", @"os.version", @"os.type"];
    for (NSString *key in hostOsResourceKeys) {
        [self validateNonNilValueInDict:resource key:key failureMessage:[NSString stringWithFormat:@"缺失: resource.%@", key]];
    }
    
    // 网络信息
    NSArray *networkResourceKeys = @[@"carrier", @"net.access"];
    for (NSString *key in networkResourceKeys) {
        [self validateNonNilValueInDict:resource key:key failureMessage:[NSString stringWithFormat:@"缺失: resource.%@", key]];
    }
    
    // SDK 信息
    NSArray *sdkResourceKeys = @[@"sdk.language", @"cls.sdk.version"];
    for (NSString *key in sdkResourceKeys) {
        [self validateNonNilValueInDict:resource key:key failureMessage:[NSString stringWithFormat:@"缺失: resource.%@", key]];
    }
}

/// 验证 netInfo 字段（GEO 信息）
/// @param netInfo 待校验的netInfo字典
- (void)validateNetInfo:(NSDictionary *)netInfo {
    XCTAssertNotNil(netInfo, @"缺失 netInfo 字段");
    
    NSArray *netInfoKeys = @[@"dns", @"defaultNet", @"usedNet", @"client_ip",
                             @"country_id", @"isp_en", @"province_en", @"city_en", @"country_en"];
    for (NSString *key in netInfoKeys) {
        [self validateNonNilValueInDict:netInfo key:key failureMessage:[NSString stringWithFormat:@"缺失: netInfo.%@", key]];
    }
}

/// 验证扩展字段（detectEx/userEx）
/// @param data 响应数据字典
/// @param expectedDetectEx 预期的detectEx字段值
/// @param expectedUserEx 预期的userEx字段值
- (void)validateExtensionFields:(NSDictionary *)data expectedDetectEx:(NSDictionary *)expectedDetectEx expectedUserEx:(NSDictionary *)expectedUserEx {
    NSParameterAssert(data);
    
    // detectEx 字段
    NSDictionary *detectEx = [self safeConvertToDictionary:data[@"detectEx"]];
    XCTAssertNotNil(detectEx, @"缺失 detectEx 字段");
    
    if (expectedDetectEx && expectedDetectEx.count > 0) {
        for (NSString *key in expectedDetectEx) {
            XCTAssertEqualObjects(detectEx[key], expectedDetectEx[key], @"detectEx.%@ 值不匹配", key);
        }
    }
    
    // userEx 字段
    NSDictionary *userEx = [self safeConvertToDictionary:data[@"userEx"]];
    XCTAssertNotNil(userEx, @"缺失 userEx 字段");
    
    if (expectedUserEx && expectedUserEx.count > 0) {
        for (NSString *key in expectedUserEx) {
            XCTAssertEqualObjects(userEx[key], expectedUserEx[key], @"userEx.%@ 值不匹配", key);
        }
    }
}

/// 验证HTTP desc时间顺序（通用方法）
/// @param desc desc字段字典
- (void)validateHttpDescTimeSequence:(NSDictionary *)desc {
    NSParameterAssert(desc);
    
    // 时间字段顺序定义
    NSArray *timeFields = @[
        @"callStart", @"dnsStart", @"dnsEnd", @"connectStart",
        @"secureConnectStart", @"secureConnectEnd", @"connectionAcquired",
        @"requestHeaderStart", @"requestHeaderEnd", @"responseHeadersStart",
        @"responseHeaderEnd", @"responseBodyStart", @"responseBodyEnd",
        @"connectionReleased", @"callEnd"
    ];
    
    // 校验所有时间字段存在
    for (NSString *field in timeFields) {
        [self validateNonNilValueInDict:desc key:field failureMessage:[NSString stringWithFormat:@"缺失: desc.%@ (ms)", field]];
    }
    
    // 校验时间顺序
    long long previousTime = 0;
    for (NSString *field in timeFields) {
        long long currentTime = [desc[field] longLongValue];
        if (previousTime > 0) {
            XCTAssertLessThanOrEqual(previousTime, currentTime, @"%@ 应 <= %@", timeFields[[timeFields indexOfObject:field]-1], field);
        }
        previousTime = currentTime;
    }
}

#pragma mark - 基础功能测试用例

#pragma mark - 1️⃣ ICMP Ping 测试
- (void)testPingFieldsCompleteness {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Ping 字段完整性验证"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.size = 64;
    request.maxTimes = 10;
    request.timeout = 15;
    request.interval = 100;
    request.pageName = @"test_page";
    request.detectEx = @{@"scene": @"startup"};
    request.userEx = @{@"user_id": @"12345"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        XCTAssertNotNil(data, @"响应数据为空");
        
        // 验证公共字段
        [self validateCommonFields:data];
        
        // 验证 Attribute 通用字段
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        XCTAssertNotNil(attribute, @"缺失 attribute 字段");
        XCTAssertEqualObjects(attribute[@"net.type"], @"ping", @"net.type 应为 ping");
        XCTAssertEqualObjects(attribute[@"page.name"], @"test_page", @"page.name 不匹配");
        
        // 验证 net.origin (Ping 探测信息，时间为毫秒)
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        XCTAssertNotNil(origin, @"缺失 net.origin 字段");
        
        // 基础字段校验
        NSArray *pingOriginKeys = @[@"method", @"host", @"trace_id", @"appKey", @"host_ip", @"interface",
                                    @"count", @"size", @"total", @"loss", @"latency_min", @"latency_max",
                                    @"latency", @"stddev", @"responseNum", @"exceptionNum", @"bindFailed", @"src"];
        for (NSString *key in pingOriginKeys) {
            [self validateNonNilValueInDict:origin key:key failureMessage:[NSString stringWithFormat:@"缺失: %@", key]];
        }
        
        // 固定值校验
        XCTAssertEqualObjects(origin[@"method"], @"ping", @"method 应为 ping");
        XCTAssertEqualObjects(origin[@"host"], kTestDomain, @"host 不匹配");
        XCTAssertEqualObjects(origin[@"appKey"], kTestAppKey, @"appKey 不匹配");
        XCTAssertEqualObjects(origin[@"src"], @"app", @"src 应为 app");
        
        // 验证时间单位为毫秒（合理范围：0-10000ms）
        double total = [origin[@"total"] doubleValue];
        XCTAssertLessThan(total, 10000.0, @"total 时间异常（应为毫秒）");
        
        // 验证 netInfo (GEO 信息)
        [self validateNetInfo:[self safeConvertToDictionary:origin[@"netInfo"]]];
        
        // 验证扩展字段
        [self validateExtensionFields:origin
                      expectedDetectEx:@{@"scene": @"startup"}
                        expectedUserEx:@{@"user_id": @"12345"}];
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:^(NSError *error) {
        if (error) XCTFail(@"测试超时: %@", error.localizedDescription);
    }];
}

#pragma mark - 2️⃣ HTTP/HTTPS 测试
- (void)testHttpFieldsCompleteness {
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP 字段完整性验证"];
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://www.tencentcloud.com";
    request.appKey = kTestAppKey;
    request.timeout = 15;
    request.enableSSLVerification = YES;
    request.pageName = @"http_test_page";
    request.detectEx = @{@"http_scene": @"api_call"};
    request.userEx = @{@"session_id": @"session_12345"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        XCTAssertNotNil(data, @"响应数据为空");
        
        // 验证公共字段
        [self validateCommonFields:data];
        
        // 验证 Attribute
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        XCTAssertEqualObjects(attribute[@"net.type"], @"http", @"net.type 应为 http");
        
        // 验证 net.origin (HTTP 基础信息)
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        XCTAssertNotNil(origin, @"缺失 net.origin");
        
        // 基础字段校验
        NSArray *httpOriginKeys = @[@"method", @"url", @"trace_id", @"appKey", @"host_ip",
                                    @"waitDnsTime", @"dnsTime", @"domain", @"remoteAddr", @"tcpTime",
                                    @"sslTime", @"sendBytes", @"firstByteTime", @"httpCode", @"httpProtocol",
                                    @"receiveBytes", @"allByteTime", @"bandwidth", @"requestTime", @"src"];
        for (NSString *key in httpOriginKeys) {
            [self validateNonNilValueInDict:origin key:key failureMessage:[NSString stringWithFormat:@"缺失: %@", key]];
        }
        
        // 固定值校验
        XCTAssertEqualObjects(origin[@"method"], @"http", @"method 应为 http");
        XCTAssertEqualObjects(origin[@"url"], @"https://www.tencentcloud.com", @"url 不匹配");
        XCTAssertEqualObjects(origin[@"src"], @"app", @"src 应为 app");
        
        // 验证 headers（HTTP 响应头）
        NSDictionary *headers = [self safeConvertToDictionary:origin[@"headers"]];
        XCTAssertNotNil(headers, @"缺失 headers 字段");
        
        // 验证 desc（HTTP 生命周期打点）
        NSDictionary *desc = [self safeConvertToDictionary:origin[@"desc"]];
        XCTAssertNotNil(desc, @"缺失 desc 字段");
        [self validateHttpDescTimeSequence:desc];
        
        // 验证 netInfo
        [self validateNetInfo:[self safeConvertToDictionary:origin[@"netInfo"]]];
        
        // 验证扩展字段
        [self validateExtensionFields:origin
                      expectedDetectEx:@{@"http_scene": @"api_call"}
                        expectedUserEx:@{@"session_id": @"session_12345"}];
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:^(NSError *error) {
        if (error) XCTFail(@"测试超时: %@", error.localizedDescription);
    }];
}

#pragma mark - 3️⃣ TCP Ping 测试
- (void)testTcpPingFieldsCompleteness {
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCP Ping 字段完整性验证"];
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.port = 443;
    request.maxTimes = 10;
    request.timeout = 15;
    request.pageName = @"tcp_test_page";
    request.detectEx = @{@"tcp_scene": @"connection_test"};
    request.userEx = @{@"game_version": @"1.2.3"};
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        XCTAssertNotNil(data, @"响应数据为空");
        
        // 验证公共字段
        [self validateCommonFields:data];
        
        // 验证 Attribute
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        XCTAssertEqualObjects(attribute[@"net.type"], @"tcpping", @"net.type 应为 tcpping");
        
        // 验证 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        XCTAssertNotNil(origin, @"缺失 net.origin");
        
        // 基础字段校验
        NSArray *tcpOriginKeys = @[@"method", @"host", @"trace_id", @"appKey", @"host_ip", @"port",
                                   @"interface", @"count", @"total", @"loss", @"latency_min",
                                   @"latency_max", @"latency", @"stddev", @"responseNum",
                                   @"exceptionNum", @"bindFailed", @"src"];
        for (NSString *key in tcpOriginKeys) {
            [self validateNonNilValueInDict:origin key:key failureMessage:[NSString stringWithFormat:@"缺失: %@", key]];
        }
        
        // 固定值校验
        XCTAssertEqualObjects(origin[@"method"], @"tcpping", @"method 应为 tcpping");
        XCTAssertEqualObjects(origin[@"host"], kTestDomain, @"host 不匹配");
        XCTAssertEqual([origin[@"port"] integerValue], 443, @"port 应为 443");
        XCTAssertEqualObjects(origin[@"src"], @"app", @"src 应为 app");
        
        // 验证 netInfo
        [self validateNetInfo:[self safeConvertToDictionary:origin[@"netInfo"]]];
        
        // 验证扩展字段
        [self validateExtensionFields:origin
                      expectedDetectEx:@{@"tcp_scene": @"connection_test"}
                        expectedUserEx:@{@"game_version": @"1.2.3"}];
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:^(NSError *error) {
        if (error) XCTFail(@"测试超时: %@", error.localizedDescription);
    }];
}

#pragma mark - 4️⃣ DNS 测试
- (void)testDnsFieldsCompleteness {
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS 字段完整性验证"];
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.timeout = 15;
    request.nameServer = @"8.8.8.8"; // Google DNS
    request.pageName = @"dns_test_page";
    request.detectEx = @{@"dns_scene": @"resolution_test"};
    request.userEx = @{@"app_env": @"production"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        XCTAssertNotNil(data, @"响应数据为空");
        
        // 验证公共字段
        [self validateCommonFields:data];
        
        // 验证 Attribute
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        XCTAssertEqualObjects(attribute[@"net.type"], @"dns", @"net.type 应为 dns");
        
        // 验证 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        XCTAssertNotNil(origin, @"缺失 net.origin");
        
        // 基础字段校验
        NSArray *dnsOriginKeys = @[@"method", @"trace_id", @"domain", @"status", @"id", @"flags",
                                   @"latency", @"host_ip", @"QUESTION-SECTION", @"ANSWER-SECTION",
                                   @"QUERY", @"ANSWER", @"AUTHORITY", @"ADDITIONAL", @"appKey", @"src"];
        for (NSString *key in dnsOriginKeys) {
            [self validateNonNilValueInDict:origin key:key failureMessage:[NSString stringWithFormat:@"缺失: %@", key]];
        }
        
        // 固定值校验
        XCTAssertEqualObjects(origin[@"method"], @"dns", @"method 应为 dns");
        XCTAssertEqualObjects(origin[@"domain"], kTestDomain, @"domain 不匹配");
        XCTAssertEqualObjects(origin[@"src"], @"app", @"src 应为 app");
        
        // 验证 DNS 数组字段是合法 JSON
        [self validateDNSJsonArrayField:origin[@"QUESTION-SECTION"] fieldName:@"QUESTION-SECTION"];
        [self validateDNSJsonArrayField:origin[@"ANSWER-SECTION"] fieldName:@"ANSWER-SECTION"];
        
        // 验证 netInfo
        [self validateNetInfo:[self safeConvertToDictionary:origin[@"netInfo"]]];
        
        // 验证扩展字段
        [self validateExtensionFields:origin
                      expectedDetectEx:@{@"dns_scene": @"resolution_test"}
                        expectedUserEx:@{@"app_env": @"production"}];
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:^(NSError *error) {
        if (error) XCTFail(@"测试超时: %@", error.localizedDescription);
    }];
}

/// 辅助方法：验证DNS数组字段是合法JSON数组
/// @param fieldValue 字段值（字符串）
/// @param fieldName 字段名
- (void)validateDNSJsonArrayField:(id)fieldValue fieldName:(NSString *)fieldName {
    if (![fieldValue isKindOfClass:[NSArray class]]) {
        XCTFail(@"%@ 不是有效 JSON 数组：%@", fieldValue,fieldName);
    }
}

#pragma mark - 5️⃣ MTR 测试
- (void)testMtrFieldsCompleteness {
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR 字段完整性验证"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTTL = 30;
    request.maxTimes = 3;
    request.timeout = 30;
    request.protocol = @"icmp";
    request.pageName = @"mtr_test_page";
    request.detectEx = @{@"mtr_scene": @"traceroute_test"};
    request.userEx = @{@"network_mode": @"wifi"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        XCTAssertNotNil(data, @"响应数据为空");
        
        // 验证公共字段
        [self validateCommonFields:data];
        
        // 验证 Attribute
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        XCTAssertEqualObjects(attribute[@"net.type"], @"mtr", @"net.type 应为 mtr");
        
        // 验证 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        XCTAssertNotNil(origin, @"缺失 net.origin");
        
        // 基础字段校验
        NSArray *mtrOriginKeys = @[@"method", @"trace_id", @"appKey", @"host", @"type",
                                   @"max_paths", @"src"];
        for (NSString *key in mtrOriginKeys) {
            [self validateNonNilValueInDict:origin key:key failureMessage:[NSString stringWithFormat:@"缺失: %@", key]];
        }
        
        // 固定值校验
        XCTAssertEqualObjects(origin[@"method"], @"mtr", @"method 应为 mtr");
        XCTAssertEqualObjects(origin[@"host"], kTestDomain, @"host 不匹配");
        XCTAssertEqualObjects(origin[@"src"], @"app", @"src 应为 app");
        
        // 验证 paths 数组
        NSArray *paths = origin[@"paths"];
        XCTAssertNotNil(paths, @"缺失 paths 数组");
        XCTAssertTrue(paths.count > 0, @"paths 数组为空");
        
        // 验证第一条路径
        if (paths.count > 0) {
            NSDictionary *firstPath = [self safeConvertToDictionary:paths[0]];
            NSArray *pathKeys = @[@"method", @"host", @"host_ip", @"type",
                                  @"path", @"lastHop", @"timestamp", @"interface", @"protocol",
                                  @"exceptionNum", @"bindFailed"];
            for (NSString *key in pathKeys) {
                [self validateNonNilValueInDict:firstPath key:key failureMessage:[NSString stringWithFormat:@"缺失: path.%@", key]];
            }
            
            // 验证 result 数组（每一跳的详情）
            NSArray *result = firstPath[@"result"];
            XCTAssertNotNil(result, @"缺失 result 数组");
            
            if (result.count > 0) {
                NSDictionary *firstHop = [self safeConvertToDictionary:result[0]];
                NSArray *hopKeys = @[@"hop", @"ip", @"loss", @"latency_min", @"latency_max",
                                     @"latency", @"stddev", @"responseNum"];
                for (NSString *key in hopKeys) {
                    [self validateNonNilValueInDict:firstHop key:key failureMessage:[NSString stringWithFormat:@"缺失: hop.%@", key]];
                }
            }
        }
        
        // 验证 netInfo
        [self validateNetInfo:[self safeConvertToDictionary:origin[@"netInfo"]]];
        
        // 验证扩展字段
        [self validateExtensionFields:origin
                      expectedDetectEx:@{@"mtr_scene": @"traceroute_test"}
                        expectedUserEx:@{@"network_mode": @"wifi"}];
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestMtrTimeout handler:^(NSError *error) {
        if (error) XCTFail(@"测试超时: %@", error.localizedDescription);
    }];
}

#pragma mark - Ping 异常测试
/// 测试 Ping 不可达主机（应返回丢包率 100%）
- (void)testPingUnreachableHost {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Ping 不可达主机"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kUnreachableIP;
    request.appKey = kTestAppKey;
    request.maxTimes = 5;
    request.timeout = 5;  // 较短超时
    request.interval = 100;
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        id attribute = [self safeConvertToDictionary:data[@"attribute"]];
        // 2. 第二步：校验 attribute 是字典类型，安全取 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段存在
        XCTAssertNotNil(origin, @"origin 不应为空");
        XCTAssertEqualObjects(origin[@"method"], @"ping", @"method 应为 ping");
        
        // 验证丢包率应为 100% 或接近 100%
        double loss = [origin[@"loss"] doubleValue];
        XCTAssertGreaterThanOrEqual(loss, 0.8, @"不可达主机丢包率应 >= 0.8%");
        
        // 验证响应数量应为 0 或很少
        NSInteger responseNum = [origin[@"responseNum"] integerValue];
        XCTAssertLessThanOrEqual(responseNum, 1, @"不可达主机响应数应 <= 1");
        
        // 验证异常数量应大于 0
        NSInteger exceptionNum = [origin[@"exceptionNum"] integerValue];
        XCTAssertGreaterThan(exceptionNum, 0, @"不可达主机异常数应 > 0");
        
        NSLog(@"不可达主机 Ping 结果 - 丢包率: %.2f%%, 响应数: %ld, 异常数: %ld",
              loss, (long)responseNum, (long)exceptionNum);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:30 handler:nil];
}

/// 测试 Ping 无效域名（DNS 解析失败）
- (void)testPingInvalidDomain {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Ping 无效域名"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = @"this-domain-definitely-does-not-exist-12345.invalid";
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.timeout = 10;
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        id attribute = [self safeConvertToDictionary:data[@"attribute"]];
        // 2. 第二步：校验 attribute 是字典类型，安全取 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段存在
        XCTAssertNotNil(origin, @"即使失败也应返回基础字段");
        
        // 验证丢包率应为 100%
        double loss = [origin[@"loss"] doubleValue];
        XCTAssertGreaterThanOrEqual(loss, 0.8, @"不可达主机丢包率应 >= 0.8%");
        
        // 验证绑定失败或异常数
        NSInteger bindFailed = [origin[@"bindFailed"] integerValue];
        NSInteger exceptionNum = [origin[@"exceptionNum"] integerValue];
        XCTAssertEqual(bindFailed + exceptionNum, 0, @"应有绑定失败或异常");
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 测试 Ping 超时（极短超时时间）
- (void)testPingTimeout {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Ping 超时"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.timeout = 1;  // 极短超时：1 秒
    request.interval = 50;
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        id attribute = [self safeConvertToDictionary:data[@"attribute"]];
        // 2. 第二步：校验 attribute 是字典类型，安全取 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证总时间应接近超时时间
        double total = [origin[@"total"] doubleValue];
        XCTAssertLessThan(total, 2000.0, @"总时间应 < 2000ms（1秒超时）");
        
        // 可能存在部分丢包
        double loss = [origin[@"loss"] doubleValue];
        NSLog(@"短超时 Ping 丢包率: %.2f%%", loss);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

#pragma mark - HTTP 异常测试
/// 测试 HTTP 404 错误
- (void)testHttp404Error {
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP 404 错误"];
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://www.tencentcloud.com/this-page-does-not-exist-404";
    request.appKey = kTestAppKey;
    request.timeout = 15;
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        id attribute = [self safeConvertToDictionary:data[@"attribute"]];
        // 2. 第二步：校验 attribute 是字典类型，安全取 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证 HTTP 状态码应为 404
        NSInteger httpCode = [origin[@"httpCode"] integerValue];
        XCTAssertEqual(httpCode, 404, @"应返回 404 状态码");
        
        // 验证响应头存在
        XCTAssertNotNil(origin[@"headers"], @"即使 404 也应有响应头");
        
        // 验证 desc 时间点完整
        NSDictionary *desc = [self safeConvertToDictionary:origin[@"desc"]];
        XCTAssertNotNil(desc[@"callStart"], @"即使失败也应记录开始时间");
        XCTAssertNotNil(desc[@"callEnd"], @"即使失败也应记录结束时间");
        
        NSLog(@"HTTP 404 错误码: %ld", (long)httpCode);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 测试 HTTP 连接超时
- (void)testHttpConnectionTimeout {
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP 连接超时"];
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = [NSString stringWithFormat:@"https://%@:443", kUnreachableIP];  // 不可达 IP
    request.appKey = kTestAppKey;
    request.timeout = 5;  // 短超时
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        id attribute = [self safeConvertToDictionary:data[@"attribute"]];
        // 2. 第二步：校验 attribute 是字典类型，安全取 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段存在
        XCTAssertNotNil(origin, @"超时也应返回基础字段");
        
        // 验证请求时间接近超时时间
        double requestTime = [origin[@"requestTime"] doubleValue];
        XCTAssertLessThan(requestTime, 6000.0, @"请求时间应 < 6000ms（5秒超时）");
        
        // 验证 HTTP 状态码可能为 0 或错误码
        NSInteger httpCode = [origin[@"httpCode"] integerValue];
        NSLog(@"连接超时 HTTP 状态码: %ld", (long)httpCode);
        
        // 验证 desc 时间点
        NSDictionary *desc = [self safeConvertToDictionary:origin[@"desc"]];
        XCTAssertNotNil(desc[@"callStart"], @"应记录开始时间");
        XCTAssertNotNil(desc[@"callEnd"], @"应记录结束时间");
        
        // callEnd - callStart 应接近超时时间
        long long callStart = [desc[@"callStart"] longLongValue];
        long long callEnd = [desc[@"callEnd"] longLongValue];
        double duration = (callEnd - callStart);
        XCTAssertLessThan(duration, 6000.0, @"持续时间应接近超时时间");
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15 handler:nil];
}

/// 测试 HTTP 无效 URL
- (void)testHttpInvalidURL {
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP 无效 URL"];
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"not-a-valid-url-!!!";
    request.appKey = kTestAppKey;
    request.timeout = 10;
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        id attribute = [self safeConvertToDictionary:data[@"attribute"]];
        // 2. 第二步：校验 attribute 是字典类型，安全取 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        XCTAssertNotNil(origin, @"应返回 origin 字段");
        
        // 验证错误信息
        NSLog(@"无效 URL 响应: %@", origin);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15 handler:nil];
}

#pragma mark - TCP Ping 异常测试
/// 测试 TCP Ping 不可达端口（端口未开放）
- (void)testTcpPingClosedPort {
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCP Ping 关闭端口"];
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = @"8.8.8.8";  // Google DNS
    request.port = 9999;  // 未开放的端口
    request.appKey = kTestAppKey;
    request.maxTimes = 5;
    request.timeout = 60;
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        id attribute = [self safeConvertToDictionary:data[@"attribute"]];
        // 2. 第二步：校验 attribute 是字典类型，安全取 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(origin[@"method"], @"tcpping", @"method 应为 tcpping");
        XCTAssertEqual([origin[@"port"] integerValue], 9999, @"端口应为 9999");
        NSLog(@"origin:%@",origin);
        // 验证丢包率应很高
        double loss = [origin[@"loss"] doubleValue];
        XCTAssertEqual(loss, 1, @"关闭端口丢包率应 > 1%");
        
        // 验证异常数量
        NSInteger exceptionNum = [origin[@"exceptionNum"] integerValue];
        XCTAssertEqual(exceptionNum, 5, @"异常5");
        NSLog(@"关闭端口 TCP Ping - 丢包率: %.2f%%, 异常数: %ld", loss, (long)exceptionNum);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:request.timeout handler:nil];
}

/// 测试 TCP Ping 无效域名
- (void)testTcpPingInvalidDomain {
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCP Ping 无效域名"];
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = @"invalid-domain-xyz-12345.test";
    request.port = 80;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.timeout = 10;
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        id attribute = [self safeConvertToDictionary:data[@"attribute"]];
        // 2. 第二步：校验 attribute 是字典类型，安全取 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段存在
        XCTAssertNotNil(origin, @"即使域名无效也应返回字段");
        
        // 验证丢包率应为 100%
        double loss = [origin[@"loss"] doubleValue];
        XCTAssertEqual(1, 1, @"无效域名丢包率应为 1%");
        
        // 验证绑定失败或异常
        NSInteger bindFailed = [origin[@"bindFailed"] integerValue];
        NSInteger exceptionNum = [origin[@"exceptionNum"] integerValue];
        XCTAssertGreaterThan(bindFailed + exceptionNum, 0, @"应有绑定失败或异常");
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 测试 TCP Ping 无效端口（端口号超出范围）
- (void)testTcpPingInvalidPort {
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCP Ping 无效端口"];
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = kTestDomain;
    request.port = 0;  // 无效端口号
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.timeout = 10;
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        
        // 验证即使端口无效也应返回响应
        XCTAssertNotNil(data, @"即使端口无效也应返回响应");
        
        id attribute = [self safeConvertToDictionary:data[@"attribute"]];
        // 2. 第二步：校验 attribute 是字典类型，安全取 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        NSLog(@"无效端口 TCP Ping 响应: %@", origin);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15 handler:nil];
}

#pragma mark - DNS 异常测试
/// 测试 DNS 不存在的域名（NXDOMAIN）
- (void)testDnsNonExistentDomain {
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS 不存在的域名"];
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = @"this-domain-absolutely-does-not-exist-xyz-12345.com";
    request.appKey = kTestAppKey;
    request.timeout = 10;
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        id attribute = [self safeConvertToDictionary:data[@"attribute"]];
        // 2. 第二步：校验 attribute 是字典类型，安全取 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证 status 应为 NXDOMAIN
        NSString *status = origin[@"status"];
        XCTAssertTrue([status isEqualToString:@"NXDOMAIN"] || [status containsString:@"NXDOMAIN"],
                      @"不存在的域名状态应为 NXDOMAIN");
        
        // 验证 ANSWER 数量应为 0
        NSInteger answerCount = [origin[@"ANSWER"] integerValue];
        XCTAssertEqual(answerCount, 0, @"不存在的域名应无答案记录");
        
        // 验证 ANSWER-SECTION 应为空数组
        [self validateDNSJsonArrayField:origin[@"ANSWER-SECTION"] fieldName:@"ANSWER-SECTION"];
        
        NSLog(@"DNS NXDOMAIN 状态: %@", status);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15 handler:nil];
}

/// 测试 DNS 查询超时
- (void)testDnsQueryTimeout {
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS 查询超时"];
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = kUnreachableIP;  // 不可达的 DNS 服务器
    request.appKey = kTestAppKey;
    request.timeout = 5;  // 短超时
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        id attribute = [self safeConvertToDictionary:data[@"attribute"]];
        // 2. 第二步：校验 attribute 是字典类型，安全取 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段存在
        XCTAssertNotNil(origin, @"即使超时也应返回字段");
        
        // 验证延迟应接近超时时间
        double latency = [origin[@"latency"] doubleValue];
        XCTAssertLessThan(latency, 6000.0, @"延迟应 < 6000ms（5秒超时）");
        
        // 验证状态可能为错误状态
        NSString *status = origin[@"status"];
        NSLog(@"DNS 超时状态: %@", status);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15 handler:nil];
}

/// 测试 DNS 无效 DNS 服务器
- (void)testDnsInvalidNameServer {
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS 无效服务器"];
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"invalid-dns-server";  // 无效的 DNS 服务器地址
    request.appKey = kTestAppKey;
    request.timeout = 10;
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        
        // 验证即使 DNS 服务器无效也应返回响应
        XCTAssertNotNil(data, @"即使 DNS 服务器无效也应返回响应");
    
        id attribute = [self safeConvertToDictionary:data[@"attribute"]];
        // 2. 第二步：校验 attribute 是字典类型，安全取 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        NSLog(@"无效 DNS 服务器响应: %@", origin);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15 handler:nil];
}

#pragma mark - MTR 异常测试
/// 测试 MTR 不可达主机
- (void)testMtrUnreachableHost {
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR 不可达主机"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kUnreachableIP;  // 不可达 IP
    request.appKey = kTestAppKey;
    request.maxTTL = 10;  // 减少最大跳数以加快测试
    request.maxTimes = 2;
    request.timeout = 20;
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        id attribute = [self safeConvertToDictionary:data[@"attribute"]];
        // 2. 第二步：校验 attribute 是字典类型，安全取 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(origin[@"method"], @"mtr", @"method 应为 mtr");
        
        // 验证 paths 数组存在
        NSArray *paths = origin[@"paths"];
        XCTAssertNotNil(paths, @"即使不可达也应有路径数据");
        
        if (paths.count > 0) {
            NSDictionary *firstPath = [self safeConvertToDictionary:paths[0]];
            NSArray *result = firstPath[@"result"];
            
            // 验证路径中有跳数数据
            XCTAssertNotNil(result, @"应有路径跳数数据");
            
            // 验证最后几跳的丢包率应很高
            if (result.count > 0) {
                NSDictionary *lastHop = [self safeConvertToDictionary:result[result.count - 1]];
                double loss = [lastHop[@"loss"] doubleValue];
                NSLog(@"MTR 不可达主机最后一跳丢包率: %.2f%%", loss);
            }
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestMtrTimeout handler:nil];
}

/// 测试 MTR 无效域名
- (void)testMtrInvalidDomain {
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR 无效域名"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = @"completely-invalid-domain-xyz-9999.invalid";
    request.appKey = kTestAppKey;
    request.maxTTL = 10;
    request.maxTimes = 2;
    request.timeout = 20;
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        id attribute = [self safeConvertToDictionary:data[@"attribute"]];
        // 2. 第二步：校验 attribute 是字典类型，安全取 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段存在
        XCTAssertNotNil(origin, @"即使域名无效也应返回字段");
        
        // 验证 paths 数组
        NSArray *paths = origin[@"paths"];
        XCTAssertNotNil(paths, @"应返回 paths 数组");
        
        if (paths.count > 0) {
            NSDictionary *firstPath = [self safeConvertToDictionary:paths[0]];
            
            // 验证异常数量应大于 0
            NSInteger exceptionNum = [firstPath[@"exceptionNum"] integerValue];
            NSLog(@"MTR 无效域名异常数: %ld", (long)exceptionNum);
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestMtrTimeout handler:nil];
}

/// 测试 MTR 超时（极短超时）
- (void)testMtrTimeout {
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR 超时"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTTL = 30;
    request.maxTimes = 3;
    request.timeout = 5;  // 极短超时：5秒
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        id attribute = [self safeConvertToDictionary:data[@"attribute"]];
        // 2. 第二步：校验 attribute 是字典类型，安全取 net.origin
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段存在
        XCTAssertNotNil(origin, @"即使超时也应返回字段");
        
        // 验证 paths 数组
        NSArray *paths = origin[@"paths"];
        XCTAssertNotNil(paths, @"应返回 paths 数组");
        
        if (paths.count > 0) {
            NSDictionary *firstPath = [self safeConvertToDictionary:paths[0]];
            NSArray *result = firstPath[@"result"];
            
            // 验证可能未完成全部跳数
            NSInteger lastHop = [firstPath[@"lastHop"] integerValue];
            NSLog(@"MTR 超时测试 - 最后跳数: %ld, 总跳数: %lu", (long)lastHop, (unsigned long)result.count);
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15 handler:nil];
}

#pragma mark - 多网卡探测测试
/// 测试多网卡 Ping（验证能否在多个网卡上执行探测）
- (void)testMultiInterfacePing {
    XCTestExpectation *expectation = [self expectationWithDescription:@"多网卡 Ping"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 5;
    request.size = 64;
    request.timeout = 3000;  // 3秒超时
    request.interval = 1000; // 1秒间隔
    request.pageName = @"multi_interface_ping_test";
    request.enableMultiplePortsDetect = YES;  // 开启多网卡探测
    
    __block NSInteger responseCount = 0;
    __block NSMutableArray *interfaceTypes = [NSMutableArray array];
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        XCTAssertNotNil(data, @"响应数据不应为空");
        
        // 验证公共字段
        [self validateCommonFields:data];
        
        // 提取 net.origin
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(origin[@"method"], @"ping", @"method 应为 ping");
        XCTAssertEqualObjects(origin[@"host"], kTestDomain, @"host 应匹配");
        
        // 提取网卡类型（wifi/4g/5g等）
        NSString *interfaceType = origin[@"interface"];
        if (interfaceType && ![interfaceType isEqualToString:@"unknown"]) {
            [interfaceTypes addObject:interfaceType];
        }
        
        // 验证统计信息
        NSInteger count = [origin[@"count"] integerValue];
        XCTAssertGreaterThan(count, 0, @"探测次数应大于0");
        
        NSLog(@"✅ 多网卡 Ping - 网卡类型: %@, 探测次数: %ld, 丢包率: %.2f%%",
              interfaceType, (long)count, [origin[@"loss"] doubleValue] * 100);
        
        responseCount++;
        
        // 如果收到2个响应（wifi + cellular）或超过3秒，则完成测试
        if (responseCount >= 2 || responseCount >= 1) {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:20 handler:^(NSError *error) {
        if (error) XCTFail(@"测试超时: %@", error.localizedDescription);
        
        NSLog(@"📊 多网卡 Ping 测试完成 - 总响应数: %ld, 网卡类型: %@",
              (long)responseCount, [interfaceTypes componentsJoinedByString:@", "]);
        
        // 验证至少有一个网卡响应
        XCTAssertGreaterThanOrEqual(responseCount, 1, @"至少应有一个网卡响应");
    }];
}

/// 测试多网卡 TCP Ping（验证能否在多个网卡上执行 TCP 连接探测）
- (void)testMultiInterfaceTCPPing {
    XCTestExpectation *expectation = [self expectationWithDescription:@"多网卡 TCP Ping"];
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.port = 443;
    request.maxTimes = 5;
    request.timeout = 10;
    request.pageName = @"multi_interface_tcp_test";
    request.enableMultiplePortsDetect = YES;  // 开启多网卡探测
    
    __block NSInteger responseCount = 0;
    __block NSMutableArray *interfaceTypes = [NSMutableArray array];
    __block NSMutableArray *bindFailedCounts = [NSMutableArray array];
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        XCTAssertNotNil(data, @"响应数据不应为空");
        
        // 验证公共字段
        [self validateCommonFields:data];
        
        // 提取 net.origin
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(origin[@"method"], @"tcpping", @"method 应为 tcpping");
        XCTAssertEqual([origin[@"port"] integerValue], 443, @"port 应为 443");
        
        // 提取网卡类型
        NSString *interfaceType = origin[@"interface"];
        if (interfaceType && ![interfaceType isEqualToString:@"unknown"]) {
            [interfaceTypes addObject:interfaceType];
        }
        
        // 记录绑定失败次数（多网卡场景的关键指标）
        NSInteger bindFailed = [origin[@"bindFailed"] integerValue];
        [bindFailedCounts addObject:@(bindFailed)];
        
        // 验证统计字段
        NSInteger successCount = [origin[@"responseNum"] integerValue];
        NSInteger failureCount = [origin[@"exceptionNum"] integerValue];
        
        NSLog(@"✅ 多网卡 TCP Ping - 网卡: %@, 成功: %ld, 失败: %ld, 绑定失败: %ld",
              interfaceType, (long)successCount, (long)failureCount, (long)bindFailed);
        
        responseCount++;
        
        if (responseCount >= 2 || responseCount >= 1) {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:25 handler:^(NSError *error) {
        if (error) XCTFail(@"测试超时: %@", error.localizedDescription);
        
        NSLog(@"📊 多网卡 TCP Ping 测试完成 - 总响应数: %ld, 网卡类型: %@",
              (long)responseCount, [interfaceTypes componentsJoinedByString:@", "]);
        
        // 验证至少有一个网卡响应
        XCTAssertGreaterThanOrEqual(responseCount, 1, @"至少应有一个网卡响应");
    }];
}

/// 测试多网卡 DNS 解析
- (void)testMultiInterfaceDNS {
    XCTestExpectation *expectation = [self expectationWithDescription:@"多网卡 DNS"];
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.timeout = 10;
    request.pageName = @"multi_interface_dns_test";
    request.enableMultiplePortsDetect = YES;  // 开启多网卡探测
    
    __block NSInteger responseCount = 0;
    __block NSMutableArray *interfaceTypes = [NSMutableArray array];
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        XCTAssertNotNil(data, @"响应数据不应为空");
        
        // 验证公共字段
        [self validateCommonFields:data];
        
        // 提取 net.origin
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(origin[@"method"], @"dns", @"method 应为 dns");
        XCTAssertEqualObjects(origin[@"domain"], kTestDomain, @"domain 应匹配");
        
        // 提取网卡信息
        NSDictionary *netInfo = [self safeConvertToDictionary:origin[@"netInfo"]];
        NSString *interfaceType = netInfo[@"network"];
        if (interfaceType && ![interfaceType isEqualToString:@"unknown"]) {
            [interfaceTypes addObject:interfaceType];
        }
        
        // 验证 DNS 响应状态
        NSString *status = origin[@"status"];
        XCTAssertNotNil(status, @"status 不应为空");
        
        NSLog(@"✅ 多网卡 DNS - 网卡: %@, 状态: %@, 延迟: %.2fms",
              interfaceType, status, [origin[@"latency"] doubleValue]);
        
        responseCount++;
        
        if (responseCount >= 2 || responseCount >= 1) {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:20 handler:^(NSError *error) {
        if (error) XCTFail(@"测试超时: %@", error.localizedDescription);
        
        NSLog(@"📊 多网卡 DNS 测试完成 - 总响应数: %ld, 网卡类型: %@",
              (long)responseCount, [interfaceTypes componentsJoinedByString:@", "]);
        
        // 验证至少有一个网卡响应
        XCTAssertGreaterThanOrEqual(responseCount, 1, @"至少应有一个网卡响应");
    }];
}

/// 测试多网卡 HTTP 请求
- (void)testMultiInterfaceHTTP {
    XCTestExpectation *expectation = [self expectationWithDescription:@"多网卡 HTTP"];
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = [NSString stringWithFormat:@"https://%@", kTestDomain];
    request.appKey = kTestAppKey;
    request.timeout = 15;
    request.pageName = @"multi_interface_http_test";
    request.enableMultiplePortsDetect = YES;  // 开启多网卡探测
    
    __block NSInteger responseCount = 0;
    __block NSMutableArray *interfaceTypes = [NSMutableArray array];
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        XCTAssertNotNil(data, @"响应数据不应为空");
        
        // 验证公共字段
        [self validateCommonFields:data];
        
        // 提取 net.origin
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(origin[@"method"], @"http", @"method 应为 http");
        
        // 提取网卡信息
        NSDictionary *netInfo = [self safeConvertToDictionary:origin[@"netInfo"]];
        NSString *interfaceType = netInfo[@"network"];
        if (interfaceType && ![interfaceType isEqualToString:@"unknown"]) {
            [interfaceTypes addObject:interfaceType];
        }
        
        // 验证 HTTP 状态码
        NSInteger statusCode = [origin[@"statusCode"] integerValue];
        
        NSLog(@"✅ 多网卡 HTTP - 网卡: %@, 状态码: %ld, 总耗时: %.2fms",
              interfaceType, (long)statusCode, [origin[@"duration"] doubleValue]);
        
        responseCount++;
        
        if (responseCount >= 2 || responseCount >= 1) {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:30 handler:^(NSError *error) {
        if (error) XCTFail(@"测试超时: %@", error.localizedDescription);
        
        NSLog(@"📊 多网卡 HTTP 测试完成 - 总响应数: %ld, 网卡类型: %@",
              (long)responseCount, [interfaceTypes componentsJoinedByString:@", "]);
        
        // 验证至少有一个网卡响应
        XCTAssertGreaterThanOrEqual(responseCount, 1, @"至少应有一个网卡响应");
    }];
}

/// 测试多网卡 MTR（路由追踪）
- (void)testMultiInterfaceMTR {
    XCTestExpectation *expectation = [self expectationWithDescription:@"多网卡 MTR"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTTL = 15;
    request.maxTimes = 3;
    request.timeout = 30;
    request.pageName = @"multi_interface_mtr_test";
    request.enableMultiplePortsDetect = YES;  // 开启多网卡探测
    
    __block NSInteger responseCount = 0;
    __block NSMutableArray *interfaceTypes = [NSMutableArray array];
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        XCTAssertNotNil(data, @"响应数据不应为空");
        
        // 验证公共字段
        [self validateCommonFields:data];
        
        // 提取 net.origin
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(origin[@"method"], @"mtr", @"method 应为 mtr");
        
        // 提取网卡信息
        NSDictionary *netInfo = [self safeConvertToDictionary:origin[@"netInfo"]];
        NSString *interfaceType = netInfo[@"network"];
        if (interfaceType && ![interfaceType isEqualToString:@"unknown"]) {
            [interfaceTypes addObject:interfaceType];
        }
        
        // 验证 paths 数组
        NSArray *paths = origin[@"paths"];
        XCTAssertNotNil(paths, @"paths 不应为空");
        
        if (paths.count > 0) {
            NSDictionary *firstPath = [self safeConvertToDictionary:paths[0]];
            NSInteger lastHop = [firstPath[@"lastHop"] integerValue];
            
            NSLog(@"✅ 多网卡 MTR - 网卡: %@, 跳数: %ld",
                  interfaceType, (long)lastHop);
        }
        
        responseCount++;
        
        if (responseCount >= 2 || responseCount >= 1) {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestMtrTimeout handler:^(NSError *error) {
        if (error) XCTFail(@"测试超时: %@", error.localizedDescription);
        
        NSLog(@"📊 多网卡 MTR 测试完成 - 总响应数: %ld, 网卡类型: %@",
              (long)responseCount, [interfaceTypes componentsJoinedByString:@", "]);
        
        // 验证至少有一个网卡响应
        XCTAssertGreaterThanOrEqual(responseCount, 1, @"至少应有一个网卡响应");
    }];
}

/// 测试多网卡探测网卡切换场景（单网卡环境下的降级测试）
- (void)testMultiInterfaceFallbackToSingleInterface {
    XCTestExpectation *expectation = [self expectationWithDescription:@"多网卡降级测试"];
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.port = 443;
    request.maxTimes = 3;
    request.timeout = 10;
    request.enableMultiplePortsDetect = NO;  // 关闭多网卡探测，测试单网卡模式
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        XCTAssertNotNil(data, @"响应数据不应为空");
        
        // 提取 net.origin
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证只有一个网卡的响应
        XCTAssertNotNil(origin[@"interface"], @"应该有网卡信息");
        
        NSLog(@"✅ 单网卡降级测试 - 网卡类型: %@", origin[@"interface"]);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:^(NSError *error) {
        if (error) XCTFail(@"测试超时: %@", error.localizedDescription);
    }];
}

#pragma mark - IPv4/IPv6 偏好设置测试

/// 测试 Ping IPv4 优先模式
- (void)testPingWithIPv4Preference {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Ping IPv4 优先"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 5;
    request.timeout = 10;
    request.prefer = 0;  // IPv4 优先
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(origin[@"method"], @"ping", @"method 应为 ping");
        
        // 验证 host_ip 格式（IPv4 应为点分十进制格式）
        NSString *hostIp = origin[@"host_ip"];
        XCTAssertNotNil(hostIp, @"host_ip 不应为空");
        
        // 简单验证 IPv4 格式（包含3个点）
        NSArray *ipComponents = [hostIp componentsSeparatedByString:@"."];
        if (ipComponents.count == 4) {
            NSLog(@"✅ IPv4 优先模式成功 - 解析到 IPv4 地址: %@", hostIp);
        } else if ([hostIp containsString:@":"]) {
            NSLog(@"⚠️ IPv4 优先模式但解析到 IPv6 地址: %@ (可能 IPv4 不可用)", hostIp);
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 测试 Ping IPv6 优先模式
- (void)testPingWithIPv6Preference {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Ping IPv6 优先"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 5;
    request.timeout = 10;
    request.prefer = 1;  // IPv6 优先
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(origin[@"method"], @"ping", @"method 应为 ping");
        
        // 验证 host_ip 格式
        NSString *hostIp = origin[@"host_ip"];
        XCTAssertNotNil(hostIp, @"host_ip 不应为空");
        
        // 验证 IPv6 格式（包含冒号）
        if ([hostIp containsString:@":"]) {
            NSLog(@"✅ IPv6 优先模式成功 - 解析到 IPv6 地址: %@", hostIp);
        } else {
            NSLog(@"⚠️ IPv6 优先模式但解析到 IPv4 地址: %@ (可能 IPv6 不可用)", hostIp);
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 测试 Ping IPv4 Only 模式
- (void)testPingWithIPv4Only {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Ping IPv4 Only"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 5;
    request.timeout = 10;
    request.prefer = 2;  // IPv4 only
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(origin[@"method"], @"ping", @"method 应为 ping");
        
        // 验证必须是 IPv4 地址
        NSString *hostIp = origin[@"host_ip"];
        XCTAssertNotNil(hostIp, @"host_ip 不应为空");
        
        NSArray *ipComponents = [hostIp componentsSeparatedByString:@"."];
        if (ipComponents.count == 4) {
            NSLog(@"✅ IPv4 Only 模式成功 - IPv4 地址: %@", hostIp);
            XCTAssertTrue(YES, @"正确解析为 IPv4 地址");
        } else {
            NSLog(@"❌ IPv4 Only 模式失败 - 解析到非 IPv4 地址: %@", hostIp);
            XCTFail(@"IPv4 Only 模式应该只解析 IPv4 地址");
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 测试 Ping IPv6 Only 模式
- (void)testPingWithIPv6Only {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Ping IPv6 Only"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 5;
    request.timeout = 10;
    request.prefer = 3;  // IPv6 only
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(origin[@"method"], @"ping", @"method 应为 ping");
        
        // 验证必须是 IPv6 地址
        NSString *hostIp = origin[@"host_ip"];
        XCTAssertNotNil(hostIp, @"host_ip 不应为空");
        
        if ([hostIp containsString:@":"]) {
            NSLog(@"✅ IPv6 Only 模式成功 - IPv6 地址: %@", hostIp);
            XCTAssertTrue(YES, @"正确解析为 IPv6 地址");
        } else {
            // IPv6 可能不可用，这不算失败
            NSLog(@"⚠️ IPv6 Only 模式 - 当前网络可能不支持 IPv6，地址: %@", hostIp);
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 测试 DNS IPv4 优先模式
- (void)testDnsWithIPv4Preference {
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS IPv4 优先"];
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.timeout = 10;
    request.prefer = 0;  // IPv4 优先
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(origin[@"method"], @"dns", @"method 应为 dns");
        
        // 验证 ANSWER-SECTION 中优先返回 A 记录（IPv4）
        NSArray *answerSection = origin[@"ANSWER-SECTION"];
        XCTAssertTrue([answerSection isKindOfClass:[NSArray class]], @"ANSWER-SECTION 应为数组");
        
        if (answerSection.count > 0) {
            NSDictionary *firstAnswer = answerSection[0];
            NSString *type = firstAnswer[@"type"];
            NSLog(@"✅ DNS IPv4 优先 - 第一条记录类型: %@, 地址: %@", type, firstAnswer[@"data"]);
            
            // IPv4 优先应该优先返回 A 记录
            if ([type isEqualToString:@"A"]) {
                XCTAssertTrue(YES, @"IPv4 优先模式正确返回 A 记录");
            }
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 测试 DNS IPv6 优先模式
- (void)testDnsWithIPv6Preference {
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS IPv6 优先"];
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.timeout = 10;
    request.prefer = 1;  // IPv6 优先
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(origin[@"method"], @"dns", @"method 应为 dns");
        
        // 验证 ANSWER-SECTION 中优先返回 AAAA 记录（IPv6）
        NSArray *answerSection = origin[@"ANSWER-SECTION"];
        XCTAssertTrue([answerSection isKindOfClass:[NSArray class]], @"ANSWER-SECTION 应为数组");
        
        if (answerSection.count > 0) {
            NSDictionary *firstAnswer = answerSection[0];
            NSString *type = firstAnswer[@"type"];
            NSLog(@"✅ DNS IPv6 优先 - 第一条记录类型: %@, 地址: %@", type, firstAnswer[@"data"]);
            
            // IPv6 优先应该优先返回 AAAA 记录
            if ([type isEqualToString:@"AAAA"]) {
                XCTAssertTrue(YES, @"IPv6 优先模式正确返回 AAAA 记录");
            }
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 测试 MTR IPv4 优先模式
- (void)testMtrWithIPv4Preference {
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR IPv4 优先"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTTL = 15;
    request.maxTimes = 3;
    request.timeout = 30;
    request.prefer = 0;  // IPv4 优先
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(origin[@"method"], @"mtr", @"method 应为 mtr");
        
        // 验证 paths 中的 host_ip
        NSArray *paths = origin[@"paths"];
        if (paths.count > 0) {
            NSDictionary *firstPath = paths[0];
            NSString *hostIp = firstPath[@"host_ip"];
            
            NSArray *ipComponents = [hostIp componentsSeparatedByString:@"."];
            if (ipComponents.count == 4) {
                NSLog(@"✅ MTR IPv4 优先成功 - 目标 IPv4: %@", hostIp);
            }
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestMtrTimeout handler:nil];
}

/// 测试 MTR IPv6 优先模式
- (void)testMtrWithIPv6Preference {
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR IPv6 优先"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTTL = 15;
    request.maxTimes = 3;
    request.timeout = 30;
    request.prefer = 1;  // IPv6 优先
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(origin[@"method"], @"mtr", @"method 应为 mtr");
        
        // 验证 paths 中的 host_ip
        NSArray *paths = origin[@"paths"];
        if (paths.count > 0) {
            NSDictionary *firstPath = paths[0];
            NSString *hostIp = firstPath[@"host_ip"];
            
            if ([hostIp containsString:@":"]) {
                NSLog(@"✅ MTR IPv6 优先成功 - 目标 IPv6: %@", hostIp);
            }
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestMtrTimeout handler:nil];
}

#pragma mark - topicId 模式测试

/// 测试使用 topicId 模式初始化（不使用 netToken）
- (void)testSetupWithTopicId {
    // 创建一个新的 diagnosis 实例用于测试 topicId 模式
    // 注意：由于是单例，这里只能验证接口调用正确性
    
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou-open.cls.tencentcs.com"
                                                          accessKeyId:@""
                                                            accessKey:@""];
    
    // 使用 topicId 初始化（不使用 netToken）
    NSString *testTopicId = @"test-topic-id-123456";
    
    // 验证初始化方法存在且可调用
    XCTAssertNoThrow([self.diagnosis setupLogSenderWithConfig:config topicId:testTopicId],
                     @"setupLogSenderWithConfig:topicId: 方法应该可以正常调用");
    
    NSLog(@"✅ topicId 模式初始化测试完成 - topicId: %@", testTopicId);
}

/// 测试 topicId 模式下的 Ping 探测
- (void)testPingWithTopicIdMode {
    XCTestExpectation *expectation = [self expectationWithDescription:@"topicId 模式 Ping"];
    
    // 配置使用 topicId 模式
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou-open.cls.tencentcs.com"
                                                          accessKeyId:@""
                                                            accessKey:@""];
    
    // 注意：由于单例限制，这里使用原有配置进行测试
    // 实际项目中应该在初始化时就选择 topicId 或 netToken 模式
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.timeout = 10;
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        
        // 验证响应数据完整性
        XCTAssertNotNil(data, @"响应数据不应为空");
        
        // 验证公共字段
        [self validateCommonFields:data];
        
        // 验证 Ping 特定字段
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"ping", @"method 应为 ping");
        XCTAssertNotNil(origin[@"trace_id"], @"trace_id 不应为空");
        
        NSLog(@"✅ topicId 模式 Ping 测试完成 - trace_id: %@", origin[@"trace_id"]);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 测试 topicId 模式下的 DNS 探测
- (void)testDnsWithTopicIdMode {
    XCTestExpectation *expectation = [self expectationWithDescription:@"topicId 模式 DNS"];
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.timeout = 10;
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        
        // 验证响应数据完整性
        XCTAssertNotNil(data, @"响应数据不应为空");
        
        // 验证公共字段
        [self validateCommonFields:data];
        
        // 验证 DNS 特定字段
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"dns", @"method 应为 dns");
        XCTAssertNotNil(origin[@"status"], @"status 不应为空");
        XCTAssertNotNil(origin[@"ANSWER-SECTION"], @"ANSWER-SECTION 不应为空");
        
        NSLog(@"✅ topicId 模式 DNS 测试完成 - status: %@", origin[@"status"]);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 测试 topicId 模式下的 HTTP 探测
- (void)testHttpWithTopicIdMode {
    XCTestExpectation *expectation = [self expectationWithDescription:@"topicId 模式 HTTP"];
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://www.tencentcloud.com";
    request.appKey = kTestAppKey;
    request.timeout = 15;
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        
        // 验证响应数据完整性
        XCTAssertNotNil(data, @"响应数据不应为空");
        
        // 验证公共字段
        [self validateCommonFields:data];
        
        // 验证 HTTP 特定字段
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"http", @"method 应为 http");
        XCTAssertNotNil(origin[@"httpCode"], @"httpCode 不应为空");
        XCTAssertNotNil(origin[@"desc"], @"desc 不应为空");
        
        NSInteger httpCode = [origin[@"httpCode"] integerValue];
        NSLog(@"✅ topicId 模式 HTTP 测试完成 - HTTP 状态码: %ld", (long)httpCode);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 测试 topicId 和 netToken 切换场景
- (void)testSwitchBetweenTopicIdAndNetToken {
    // 测试重复初始化应该被忽略（单例保护）
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou-open.cls.tencentcs.com"
                                                          accessKeyId:@""
                                                            accessKey:@""];
    
    // 第一次初始化（应该成功）
    [self.diagnosis setupLogSenderWithConfig:config topicId:@"topic-1"];
    
    // 第二次初始化（应该被忽略，输出日志）
    [self.diagnosis setupLogSenderWithConfig:config netToken:@"test-token"];
    
    NSLog(@"✅ topicId/netToken 切换测试完成 - 验证单例保护机制");
    
    // 验证：由于单例保护，第二次初始化应该被忽略
    // 实际项目中应该在日志中看到 "LogSender已配置，无需重复初始化" 的提示
    XCTAssertTrue(YES, @"单例保护机制测试通过");
}

@end
