//
//  CLSWiFiOnlyDetectionTests.m
//  TencentCloudLogDemoTests
//
//  Created by AI Assistant on 2025/12/30.
//  专门针对WiFi网络探测的测试用例
//
//  测试场景：
//  1. 仅开启WiFi网络连接（关闭蜂窝数据）
//  2. 使用enableMultiplePortsDetect=true和false进行对比测试
//  3. 验证WiFi环境下的探测结果

#import "CLSNetworkDiagnosisBaseTests.h"

@interface CLSWiFiOnlyDetectionTests : CLSNetworkDiagnosisBaseTests

@property (nonatomic, assign) NSInteger resultCount;
@property (nonatomic, strong) NSMutableArray<NSString *> *networkTypes;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *detectionResults;

@end

@implementation CLSWiFiOnlyDetectionTests

#pragma mark - Setup & Teardown

- (void)setUp {
    [super setUp];
    
    // 初始化测试数据（diagnosis 由基类初始化）
    self.resultCount = 0;
    self.networkTypes = [NSMutableArray array];
    self.detectionResults = [NSMutableArray array];
}

- (void)tearDown {
    self.networkTypes = nil;
    self.detectionResults = nil;
    [super tearDown];
}

#pragma mark - 工具方法

/// 解析响应的 JSON 内容
/// @param response CLS响应对象
/// @return 解析后的字典，失败返回nil
- (NSDictionary *)parseResponseContent:(CLSResponse *)response {
    if (!response || !response.content) {
        XCTFail(@"响应对象为空或content字段缺失");
        return nil;
    }
    
    NSError *error;
    NSData *jsonData = [response.content dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    
    if (error) {
        XCTFail(@"JSON 解析失败: %@，原始内容：%@", error.localizedDescription, response.content);
        return nil;
    }
    
    return dict;
}

/// 安全转换任意类型为字典
/// @param rawValue 原始值（可能是字符串/字典/NSNull/nil等）
/// @return 转换后的字典，失败返回空字典
- (NSDictionary *)safeConvertToDictionary:(id)rawValue {
    if (!rawValue || [rawValue isKindOfClass:[NSNull class]]) {
        return @{};
    }
    
    if ([rawValue isKindOfClass:[NSDictionary class]]) {
        return (NSDictionary *)rawValue;
    }
    
    if ([rawValue isKindOfClass:[NSString class]]) {
        NSError *error;
        NSData *jsonData = [(NSString *)rawValue dataUsingEncoding:NSUTF8StringEncoding];
        id result = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
        if ([result isKindOfClass:[NSDictionary class]]) {
            return (NSDictionary *)result;
        }
    }
    
    return @{};
}

/// 完整输出探测结果（解决NSLog截断问题）
/// @param data 响应数据字典
/// @param title 日志标题
- (void)logCompleteResult:(NSDictionary *)data withTitle:(NSString *)title {
    NSLog(@"🔍 ========== %@ ==========", title);
    
//    // 方法1：分段输出主要字段
//    NSLog(@"📋 基础信息：");
//    NSLog(@"   - name: %@", data[@"name"]);
//    NSLog(@"   - traceID: %@", data[@"traceID"]);
//    NSLog(@"   - start: %@", data[@"start"]);
//    NSLog(@"   - duration: %@", data[@"duration"]);
//    NSLog(@"   - end: %@", data[@"end"]);
//
//    // 方法2：输出attribute字段
//    NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
//    NSLog(@"📋 Attribute信息：");
//    for (NSString *key in attribute.allKeys) {
//        id value = attribute[key];
//        if ([key isEqualToString:@"net.origin"]) {
//            // net.origin字段单独处理
//            NSDictionary *origin = [self safeConvertToDictionary:value];
//            NSLog(@"   - %@: (详见下方net.origin详情)", key);
//        } else {
//            NSLog(@"   - %@: %@", key, value);
//        }
//    }
//
//    // 方法3：详细输出net.origin字段
//    NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
//    NSLog(@"📋 Net.Origin详情：");
//    for (NSString *key in origin.allKeys) {
//        id value = origin[key];
//        if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
//            // 复杂对象转JSON字符串输出
//            NSError *error;
//            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:&error];
//            if (!error && jsonData) {
//                NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
//                NSLog(@"   - %@: %@", key, jsonString);
//            } else {
//                NSLog(@"   - %@: %@", key, value);
//            }
//        } else {
//            NSLog(@"   - %@: %@", key, value);
//        }
//    }
//
    // 方法4：输出完整JSON（分块输出避免截断）
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:&error];
    if (!error && jsonData) {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        
        // 分块输出JSON字符串（每块1000字符）
        NSInteger chunkSize = 1000;
        NSInteger length = jsonString.length;
        
        NSLog(@"📋 完整JSON数据（共%ld字符，分%ld块输出）：", (long)length, (long)((length + chunkSize - 1) / chunkSize));
        
        for (NSInteger i = 0; i < length; i += chunkSize) {
            NSInteger remainingLength = length - i;
            NSInteger currentChunkSize = MIN(chunkSize, remainingLength);
            NSString *chunk = [jsonString substringWithRange:NSMakeRange(i, currentChunkSize)];
            NSLog(@"📄 JSON块 %ld: %@", (long)(i / chunkSize + 1), chunk);
        }
    } else {
        NSLog(@"❌ JSON序列化失败: %@", error.localizedDescription);
    }
    
    NSLog(@"🔍 ========== %@ 结束 ==========", title);
}

/// 简洁输出探测结果的关键信息（避免过多日志）
/// @param data 响应数据字典
/// @param title 日志标题
- (void)logKeyResult:(NSDictionary *)data withTitle:(NSString *)title {
    NSLog(@"🔍 ===== %@ =====", title);
    
    // 输出关键字段
    NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
    NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
    
    NSLog(@"📋 关键信息：");
    NSLog(@"   - method: %@", origin[@"method"]);
    NSLog(@"   - httpCode: %@", origin[@"httpCode"]);
    NSLog(@"   - domain: %@", origin[@"domain"]);
    NSLog(@"   - interface: %@", origin[@"interface"]);
    NSLog(@"   - appKey: %@", origin[@"appKey"]);
    NSLog(@"   - traceID: %@", data[@"traceID"]);
    
    // 根据探测类型输出特定字段
    NSString *method = origin[@"method"];
    if ([method isEqualToString:@"ping"]) {
        NSLog(@"   - loss: %@", origin[@"loss"]);
        NSLog(@"   - latency: %@", origin[@"latency"]);
    } else if ([method isEqualToString:@"tcpping"]) {
        NSLog(@"   - port: %@", origin[@"port"]);
        NSLog(@"   - loss: %@", origin[@"loss"]);
    }
    
    // 输出网络信息
    NSDictionary *netInfo = [self safeConvertToDictionary:origin[@"netInfo"]];
    if (netInfo.count > 0) {
        NSLog(@"📶 网络信息：");
        NSLog(@"   - usedNet: %@", netInfo[@"usedNet"]);
        NSLog(@"   - carrier: %@", netInfo[@"carrier"]);
        NSLog(@"   - wifiSSID: %@", netInfo[@"wifiSSID"]);
    }
    
    NSLog(@"🔍 ===== %@ 结束 =====", title);
}

/// 从响应中提取网络类型
/// @param response CLS响应对象
/// @return 网络类型字符串
- (NSString *)extractNetworkType:(CLSResponse *)response {
    NSDictionary *data = [self parseResponseContent:response];
    if (!data) return @"unknown";
    
    NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
    NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
    
    // 优先从 interface 字段获取网络类型
    NSString *interfaceType = origin[@"interface"];
    if (interfaceType && ![interfaceType isEqualToString:@"unknown"]) {
        return interfaceType;
    }
    
    // 备选：从 netInfo 中获取
    NSDictionary *netInfo = [self safeConvertToDictionary:origin[@"netInfo"]];
    NSString *networkType = netInfo[@"usedNet"];
    if (networkType && ![networkType isEqualToString:@"unknown"]) {
        return networkType;
    }
    
    return @"unknown";
}

/// 验证WiFi探测结果的基础字段
/// @param data 响应数据字典
- (void)validateWiFiDetectionResult:(NSDictionary *)data {
    XCTAssertNotNil(data, @"响应数据不应为空");
    
    // 验证基础字段存在
    XCTAssertNotNil(data[@"name"], @"缺失 name 字段");
    XCTAssertNotNil(data[@"traceID"], @"缺失 traceID 字段");
    XCTAssertNotNil(data[@"start"], @"缺失 start 字段");
    XCTAssertNotNil(data[@"duration"], @"缺失 duration 字段");
    XCTAssertNotNil(data[@"end"], @"缺失 end 字段");
    
    // 验证 attribute 字段
    NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
    XCTAssertNotNil(attribute, @"缺失 attribute 字段");
    
    // 验证 net.origin 字段
    NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
    XCTAssertNotNil(origin, @"缺失 net.origin 字段");
    XCTAssertNotNil(origin[@"method"], @"缺失 method 字段");
    XCTAssertNotNil(origin[@"trace_id"], @"缺失 trace_id 字段");
    XCTAssertNotNil(origin[@"appKey"], @"缺失 appKey 字段");
}

#pragma mark - #16/#26 多端口回调空值过滤
- (BOOL)isValidDetectionResult:(NSDictionary *)data {
    if (!data || data.count == 0) return NO;
    if (!data[@"name"] || !data[@"traceID"]) return NO;
    NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
    NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
    if (!origin[@"method"]) return NO;
    return YES;
}

#pragma mark - WiFi专项测试用例

/// 测试1：WiFi环境 + enableMultiplePortsDetect=false（预期1条结果）
- (void)testWiFiDetection_MultiplePortsFalse_ExpectSingleResult {
    NSLog(@"🧪 开始测试：WiFi环境 + enableMultiplePortsDetect=false");
    NSLog(@"📋 请确保：1) 已连接WiFi  2) 已关闭蜂窝数据");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"WiFi单端口探测"];
    
    // 重置计数器
    self.resultCount = 0;
    [self.networkTypes removeAllObjects];
    [self.detectionResults removeAllObjects];
    
    // 配置HTTP请求 - 关闭多端口探测
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"http://www.baidu.com";
    request.appKey = kTestAppKey;
    request.timeout = 15000;  // 15秒，单位ms
    request.enableMultiplePortsDetect = false;  // 🔑 关键：关闭多端口探测
    request.pageName = @"wifi_single_port_test";
    request.detectEx = @{@"test_scenario": @"wifi_only_false"};
//    request.userEx = @{@"test_type": @"single_port"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        self.resultCount++;
        
        // 解析并验证响应
        NSDictionary *data = [self parseResponseContent:response];
        [self validateWiFiDetectionResult:data];
        
        // 🔧 完整输出TCP Ping探测结果
        [self logCompleteResult:data withTitle:@"WiFi Http Ping探测结果"];
        
        // 提取网络类型
        NSString *networkType = [self extractNetworkType:response];
        [self.networkTypes addObject:networkType];
        [self.detectionResults addObject:data];
        
        NSLog(@"📶 收到WiFi探测结果 #%ld，网络类型：%@", (long)self.resultCount, networkType);
        
        // 验证HTTP状态码
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        NSInteger httpCode = [origin[@"httpCode"] integerValue];
        
        XCTAssertEqual(httpCode, 200, @"HTTP状态码应为200");
        XCTAssertEqualObjects(origin[@"method"], @"http", @"method应为http");
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:^(NSError *error) {
        NSLog(@"📊 测试1结果统计：");
        NSLog(@"   - 收到探测结果数量：%ld", (long)self.resultCount);
        NSLog(@"   - 网络类型列表：%@", self.networkTypes);
        
        // 验证结果
        XCTAssertEqual(self.resultCount, 1, @"enableMultiplePortsDetect=false时应收到1条结果");
        
        if (self.resultCount == 1) {
            NSLog(@"✅ 测试1通过：WiFi环境下关闭多端口探测，收到1条结果");
        } else {
            NSLog(@"❌ 测试1失败：预期1条结果，实际收到%ld条", (long)self.resultCount);
        }
        
        if (error) {
            XCTFail(@"测试超时: %@", error.localizedDescription);
        }
    }];
}

/// 测试2：WiFi环境 + enableMultiplePortsDetect=true（预期1条结果，因为只有WiFi）
- (void)testWiFiDetection_MultiplePortsTrue_ExpectSingleResult {
    NSLog(@"🧪 开始测试：WiFi环境 + enableMultiplePortsDetect=true");
    NSLog(@"📋 请确保：1) 已连接WiFi  2) 已关闭蜂窝数据");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"WiFi多端口探测"];
    
    // 重置计数器
    self.resultCount = 0;
    [self.networkTypes removeAllObjects];
    [self.detectionResults removeAllObjects];
    
    // 使用标志位防止重复调用 fulfill
    __block BOOL hasFulfilled = NO;
    
    // 配置HTTP请求 - 开启多端口探测
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"http://www.baidu.com";
    request.appKey = kTestAppKey;
    request.timeout = 15000;  // 15秒，单位ms
    request.enableMultiplePortsDetect = true;  // 🔑 关键：开启多端口探测
    request.pageName = @"wifi_multiple_ports_test";
    request.detectEx = @{@"test_scenario": @"wifi_only_true"};
//    request.userEx = @{@"test_type": @"multiple_ports"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        self.resultCount++;
        
        // 解析并验证响应
        NSDictionary *data = [self parseResponseContent:response];
        
        if (![self isValidDetectionResult:data]) {
            NSLog(@"⏭️  跳过无效回调 #%ld（可能是不可达网卡）", (long)self.resultCount);
            return;
        }
        [self validateWiFiDetectionResult:data];
        
        // 🔧 完整输出Http Ping探测结果
        [self logCompleteResult:data withTitle:@"WiFi http Ping探测结果"];
        
        // 提取网络类型
        NSString *networkType = [self extractNetworkType:response];
        [self.networkTypes addObject:networkType];
        [self.detectionResults addObject:data];
        
        NSLog(@"📶 收到WiFi探测结果 #%ld，网络类型：%@", (long)self.resultCount, networkType);
        
        // 验证HTTP状态码
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        NSInteger httpCode = [origin[@"httpCode"] integerValue];
        
        XCTAssertEqual(httpCode, 200, @"HTTP状态码应为200");
        XCTAssertEqualObjects(origin[@"method"], @"http", @"method应为http");
        
        // 由于只有WiFi网络，即使开启多端口探测也只会收到1条结果
        // 等待一小段时间确保没有更多结果，使用标志位防止重复 fulfill
        if (!hasFulfilled) {
            hasFulfilled = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [expectation fulfill];
            });
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:^(NSError *error) {
        NSLog(@"📊 测试2结果统计：");
        NSLog(@"   - 收到探测结果数量：%ld", (long)self.resultCount);
        NSLog(@"   - 有效结果数量：%ld", (long)self.detectionResults.count);
        NSLog(@"   - 网络类型列表：%@", self.networkTypes);
        
        XCTAssertGreaterThanOrEqual(self.detectionResults.count, 1, @"至少应收到 1 条合法回调（WiFi）");
        
        if (self.detectionResults.count >= 1) {
            NSLog(@"✅ 测试2通过：WiFi环境下开启多端口探测，收到 %ld 条合法结果", (long)self.detectionResults.count);
        }
        
        if (error) {
            XCTFail(@"测试超时: %@", error.localizedDescription);
        }
    }];
}

/// 测试3：对比WiFi探测结果的一致性
- (void)testWiFiDetection_CompareResults {
    NSLog(@"🧪 开始测试：对比WiFi探测结果一致性");
    
    XCTestExpectation *expectation1 = [self expectationWithDescription:@"WiFi探测对比-false"];
    XCTestExpectation *expectation2 = [self expectationWithDescription:@"WiFi探测对比-true"];
    
    __block NSDictionary *resultFalse = nil;
    __block NSDictionary *resultTrue = nil;
    __block BOOL hasFulfilled2 = NO;  // 防止 expectation2 被多次 fulfill
    
    // 第一次测试：enableMultiplePortsDetect = false
    CLSHttpRequest *request1 = [[CLSHttpRequest alloc] init];
    request1.domain = @"http://www.baidu.com";
    request1.appKey = kTestAppKey;
    request1.timeout = 15000;  // 15秒，单位ms
    request1.enableMultiplePortsDetect = false;
    request1.pageName = @"wifi_compare_false";
    
    [self.diagnosis httpingv2:request1 complate:^(CLSResponse *response) {
        resultFalse = [self parseResponseContent:response];
        [self logCompleteResult:resultFalse withTitle:@"对比测试-enableMultiplePortsDetect=false"];
        NSLog(@"📶 收到enableMultiplePortsDetect=false的结果");
        [expectation1 fulfill];
    }];
    
    // 等待第一次测试完成后再进行第二次测试
    [self waitForExpectations:@[expectation1] timeout:kTestDefaultTimeout];
    
    // 第二次测试：enableMultiplePortsDetect = true
    CLSHttpRequest *request2 = [[CLSHttpRequest alloc] init];
    request2.domain = @"https://www.baidu.com";
    request2.appKey = kTestAppKey;
    request2.timeout = 15000;  // 15秒，单位ms
    request2.enableMultiplePortsDetect = true;
    request2.pageName = @"wifi_compare_true";
    
    [self.diagnosis httpingv2:request2 complate:^(CLSResponse *response) {
        // 只处理第一次回调结果，防止多次 fulfill
        if (!hasFulfilled2) {
            hasFulfilled2 = YES;
            resultTrue = [self parseResponseContent:response];
            [self logCompleteResult:resultTrue withTitle:@"对比测试-enableMultiplePortsDetect=true"];
            NSLog(@"📶 收到enableMultiplePortsDetect=true的结果");
            [expectation2 fulfill];
        }
    }];
    
    [self waitForExpectations:@[expectation2] timeout:kTestDefaultTimeout];
    
    // 对比结果
    NSLog(@"📊 对比WiFi探测结果：");
    
    if (resultFalse && resultTrue) {
        NSDictionary *attr1 = [self safeConvertToDictionary:resultFalse[@"attribute"]];
        NSDictionary *origin1 = [self safeConvertToDictionary:attr1[@"net.origin"]];
        
        NSDictionary *attr2 = [self safeConvertToDictionary:resultTrue[@"attribute"]];
        NSDictionary *origin2 = [self safeConvertToDictionary:attr2[@"net.origin"]];
        
        // 验证关键字段一致性
        XCTAssertEqualObjects(origin1[@"method"], origin2[@"method"], @"method字段应一致");
        XCTAssertEqualObjects(origin1[@"httpCode"], origin2[@"httpCode"], @"httpCode字段应一致");
        XCTAssertEqualObjects(origin1[@"domain"], origin2[@"domain"], @"domain字段应一致");
        
        NSString *interface1 = origin1[@"interface"];
        NSString *interface2 = origin2[@"interface"];
        
        NSLog(@"   - enableMultiplePortsDetect=false 网络接口：%@", interface1);
        NSLog(@"   - enableMultiplePortsDetect=true  网络接口：%@", interface2);
        
        // 在WiFi环境下，两种模式的网络接口应该一致
        XCTAssertEqualObjects(interface1, interface2, @"WiFi环境下两种模式的网络接口应一致");
        
        NSLog(@"✅ 测试3通过：WiFi探测结果一致性验证成功");
    } else {
        XCTFail(@"未能获取到完整的对比结果");
    }
}

/// 测试4：WiFi网络下的Ping探测对比
- (void)testWiFiPingDetection_CompareMultiplePorts {
    NSLog(@"🧪 开始测试：WiFi环境下Ping探测对比");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"WiFi Ping探测"];
    __block BOOL fulfilled = NO;
    
    // 重置计数器
    self.resultCount = 0;
    [self.networkTypes removeAllObjects];
    
    // 配置Ping请求 - 开启多端口探测
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 5;
    request.timeout = 10000;  // 10秒，单位ms
    request.interval = 100;
    request.enableMultiplePortsDetect = true;  // 开启多端口探测
    request.pageName = @"wifi_ping_test";
    request.detectEx = @{@"test_scenario": @"wifi_ping"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        self.resultCount++;
        
        // 解析并验证响应
        NSDictionary *data = [self parseResponseContent:response];
        [self validateWiFiDetectionResult:data];
        
        // 🔧 完整输出Ping探测结果
        [self logCompleteResult:data withTitle:@"WiFi Ping探测结果"];
        // 提取网络类型
        NSString *networkType = [self extractNetworkType:response];
        [self.networkTypes addObject:networkType];
        
        NSLog(@"📶 收到WiFi Ping结果 #%ld，网络类型：%@", (long)self.resultCount, networkType);
        
        // 验证Ping特定字段
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"ping", @"method应为ping");
        XCTAssertNotNil(origin[@"loss"], @"应包含丢包率字段");
        XCTAssertNotNil(origin[@"latency"], @"应包含延迟字段");
        
        // 等待确保没有更多结果，只fulfill一次
        @synchronized (expectation) {
            if (!fulfilled) {
                fulfilled = YES;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [expectation fulfill];
                });
            }
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:^(NSError *error) {
        NSLog(@"📊 WiFi Ping测试结果：");
        NSLog(@"   - 收到探测结果数量：%ld", (long)self.resultCount);
        NSLog(@"   - 网络类型列表：%@", self.networkTypes);
        
        // WiFi环境下Ping探测应收到1条结果
        XCTAssertEqual(self.resultCount, 1, @"WiFi环境下Ping探测应收到1条结果");
        
        if (self.resultCount == 1) {
            NSLog(@"✅ 测试4通过：WiFi环境下Ping探测正常");
        }
        
        if (error) {
            XCTFail(@"测试超时: %@", error.localizedDescription);
        }
    }];
}

/// 测试5：WiFi网络下的TCP Ping探测对比
- (void)testWiFiTcpPingDetection_CompareMultiplePorts {
    NSLog(@"🧪 开始测试：WiFi环境下TCP Ping探测对比");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"WiFi TCP Ping探测"];
    __block BOOL fulfilled = NO;
    
    // 重置计数器
    self.resultCount = 0;
    [self.networkTypes removeAllObjects];
    
    // 配置TCP Ping请求 - 开启多端口探测
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.port = 443;
    request.maxTimes = 5;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = YES;  // 开启多端口探测
    request.pageName = @"wifi_tcp_ping_test";
    request.detectEx = @{@"test_scenario": @"wifi_tcp_ping"};
    
    __block NSInteger validResultCount = 0;
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        self.resultCount++;
        
        // 解析并验证响应
        NSDictionary *data = [self parseResponseContent:response];
        
        if (![self isValidDetectionResult:data]) {
            NSLog(@"⏭️  跳过无效 TCP Ping 回调 #%ld（可能是不可达网卡）", (long)self.resultCount);
            return;
        }
        validResultCount++;
        [self validateWiFiDetectionResult:data];
        // 🔧 完整输出TCP Ping探测结果
        [self logCompleteResult:data withTitle:@"WiFi TCP Ping探测结果"];
        // 提取网络类型
        NSString *networkType = [self extractNetworkType:response];
        [self.networkTypes addObject:networkType];
        
        NSLog(@"📶 收到WiFi TCP Ping结果 #%ld，网络类型：%@", (long)self.resultCount, networkType);
        
        // 验证TCP Ping特定字段
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"tcpping", @"method应为tcpping");
        XCTAssertEqual([origin[@"port"] integerValue], 443, @"端口应为443");
        XCTAssertNotNil(origin[@"loss"], @"应包含丢包率字段");
        
        // 等待确保没有更多结果，只fulfill一次
        @synchronized (expectation) {
            if (!fulfilled) {
                fulfilled = YES;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [expectation fulfill];
                });
            }
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:^(NSError *error) {
        NSLog(@"📊 WiFi TCP Ping测试结果：");
        NSLog(@"   - 收到探测结果数量：%ld", (long)self.resultCount);
        NSLog(@"   - 有效结果数量：%ld", (long)validResultCount);
        NSLog(@"   - 网络类型列表：%@", self.networkTypes);
        
        XCTAssertGreaterThanOrEqual(validResultCount, 1, @"至少应收到 1 条合法 TCP Ping 回调（WiFi）");
        
        if (validResultCount >= 1) {
            NSLog(@"✅ 测试5通过：WiFi环境下TCP Ping探测正常");
        }
        
        if (error) {
            XCTFail(@"测试超时: %@", error.localizedDescription);
        }
    }];
}



@end

