//
//  ZhiyanPingDetectionTests.m
//  TencentCloudLogDemoTests
//
//  Created by AI Assistant on 2025/12/30.
//  智研PING探测专项测试用例
//
//  Ping探测参数：domain、detectEx、enableMultiplePortsDetect、maxTimes、size、timeout
//  注意：userEx 已移除，统一从 ClsNetworkDiagnosis 获取
//

#import "CLSNetworkDiagnosisBaseTests.h"

@interface ZhiyanPingDetectionTests : CLSNetworkDiagnosisBaseTests
@end

@implementation ZhiyanPingDetectionTests

#pragma mark - 基本功能测试

/// 【PING-001】验证Ping探测基本功能及所有字段完整性
- (void)testPingBasicFunctionality {
    NSLog(@"🧪 开始执行用例PING-001：Ping探测基本功能验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING基本功能"];
    __block BOOL fulfilled = NO;
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = @"www.tencentcloud.com";
    request.appKey = kTestAppKey;
    request.maxTimes = 5;      // 单次探测次数
    request.size = 64;         // 包大小
    request.timeout = 10000;   // 超时时间(ms)
    request.enableMultiplePortsDetect = NO;  // 基本测试使用单网卡模式
    request.detectEx = @{@"case_id": @"PING-001", @"priority": @"P0"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"PING基本功能验证结果"];
            
            // 1. 公共字段校验
            [self validateCommonFields:data];
            [self validateResourceFields:data];
            [self validateAttributeFields:data expectedType:@"ping"];
            [self validateNetOriginFields:data expectedMethod:@"ping"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 2. Ping专用字段校验
            [self validatePingOriginFields:origin];
            [self validatePingStatisticsFields:origin expectedCount:5 expectedSize:64+8];
            
            // 3. 网络环境信息校验
            [self validateNetInfo:[self safeConvertToDictionary:origin[@"netInfo"]]];
            
            // 4. 扩展字段校验
            [self validateExtensionFields:origin 
                         expectedDetectEx:@{@"case_id": @"PING-001"}];
            
            // 5. 全局 userEx 字段校验（验证 setUserEx 设置成功）
            [self validateUserExFields:origin expectedUserEx:nil];
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

#pragma mark - 参数验证测试

/// 【PING-002】验证domain参数
- (void)testPingDomainParameter {
    NSLog(@"🧪 开始执行用例PING-002：domain参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-domain"];
    __block BOOL fulfilled = NO;
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = @"www.tencent.com";  // 使用不同域名
    request.appKey = kTestAppKey;
    request.maxTimes = 5;
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"PING-002"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"PING domain验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 验证host字段应等于设置的domain
            XCTAssertEqualObjects(origin[@"host"], @"www.tencent.com", @"host应等于设置的domain");
            XCTAssertNotNil(origin[@"host_ip"], @"host_ip不应为空");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【PING-003】验证maxTimes参数 - 单次探测次数
- (void)testPingMaxTimesParameter {
    NSLog(@"🧪 开始执行用例PING-003：maxTimes参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-maxTimes"];
    __block BOOL fulfilled = NO;
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;  // 设置探测3次
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"PING-003"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"PING maxTimes验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 验证count字段应等于maxTimes
            XCTAssertEqual([origin[@"count"] integerValue], 3, @"count应等于设置的maxTimes=3");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【PING-004】验证size参数 - 包大小
- (void)testPingSizeParameter {
    NSLog(@"🧪 开始执行用例PING-004：size参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-size"];
    __block BOOL fulfilled = NO;
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.size = 128;  // 设置128字节
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"PING-004"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"PING size验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 验证size字段
            XCTAssertEqual([origin[@"size"] integerValue], 128+8, @"size应等于设置的128");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【PING-005】验证timeout参数 - 超时触发
- (void)testPingTimeoutParameter {
    NSLog(@"🧪 开始执行用例PING-005：timeout参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-timeout"];
    __block BOOL fulfilled = NO;
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = @"192.0.2.1";  // 不可达IP
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.timeout = 1000;  // 1秒超时，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"PING-005"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"PING timeout验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 超时场景应该有丢包
            double loss = [origin[@"loss"] doubleValue];
            NSLog(@"📍 超时场景丢包率: %f", loss);
            XCTAssertGreaterThan(loss, 0, @"不可达IP应产生丢包");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【PING-006】验证enableMultiplePortsDetect参数
- (void)testPingEnableMultiplePortsDetect {
    NSLog(@"🧪 开始执行用例PING-006：enableMultiplePortsDetect参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-multiPorts"];
    __block BOOL fulfilled = NO;
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.enableMultiplePortsDetect = YES;
    request.detectEx = @{@"case_id": @"PING-006"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"PING multiPorts验证结果"];
            
            // 验证基本字段存在
            [self validateCommonFields:data];
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【PING-007】验证detectEx扩展字段
- (void)testPingExtensionFields {
    NSLog(@"🧪 开始执行用例PING-007：扩展字段验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-extension"];
    __block BOOL fulfilled = NO;
    
    NSDictionary *detectEx = @{
        @"case_id": @"PING-007",
        @"business_type": @"network_monitor",
        @"priority": @"P1"
    };
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.enableMultiplePortsDetect = NO;
    request.detectEx = detectEx;
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"PING扩展字段验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 验证扩展字段完整传递
            [self validateExtensionFields:origin expectedDetectEx:detectEx];
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

#pragma mark - 字段完整性测试

/// 【PING-008】验证所有返回字段完整性
- (void)testPingAllFieldsCompleteness {
    NSLog(@"🧪 开始执行用例PING-008：字段完整性验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-字段完整性"];
    __block BOOL fulfilled = NO;
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 5;
    request.size = 64;
    request.timeout = 10000;  // 10秒，单位ms
    request.pageName = @"ping_fields_test";
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"PING-008"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"PING字段完整性验证结果"];
            
            // 1. 公共字段
            [self validateCommonFields:data];
            [self validateResourceFields:data];
            
            // 2. Attribute字段
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            XCTAssertEqualObjects(attribute[@"net.type"], @"ping", @"net.type应为ping");
            XCTAssertEqualObjects(attribute[@"page.name"], @"ping_fields_test", @"page.name应匹配");
            
            // 3. net.origin字段
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            [self validatePingOriginFields:origin];
            
            // 4. 验证src字段
            XCTAssertEqualObjects(origin[@"src"], @"app", @"src应为app");
            
            // 5. netInfo字段
            [self validateNetInfo:[self safeConvertToDictionary:origin[@"netInfo"]]];
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

#pragma mark - 异常场景测试

/// 【PING-ERR-001】异常场景 - 无效域名
- (void)testPingInvalidDomain {
    NSLog(@"🧪 开始执行用例PING-ERR-001：无效域名");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-无效域名"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = @"invalid.domain.not.exist.test";
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.timeout = 3000;  // 3秒，单位ms
    request.detectEx = @{@"case_id": @"PING-ERR-001"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"PING无效域名结果"];
            
            // 无效域名应该也有返回数据
            XCTAssertNotNil(data, @"无效域名也应有返回数据");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【PING-ERR-002】异常场景 - 不可达IP
- (void)testPingUnreachableIP {
    NSLog(@"🧪 开始执行用例PING-ERR-002：不可达IP");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-不可达IP"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = @"192.0.2.1";  // TEST-NET-1，保证不可达
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.timeout = 2000;  // 2秒，单位ms
    request.detectEx = @{@"case_id": @"PING-ERR-002"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"PING不可达IP结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 不可达IP应该产生100%丢包
            double loss = [origin[@"loss"] doubleValue];
            XCTAssertGreaterThan(loss, 0, @"不可达IP应产生丢包");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

#pragma mark - IP协议偏好测试

/// 【PING-012】验证prefer参数 - IPv4优先 (prefer=0)
- (void)testPingPreferIPv4First {
    NSLog(@"🧪 开始执行用例PING-012：prefer参数验证 - IPv4优先");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-prefer-IPv4优先"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.prefer = 0;  // IPv4优先
    request.detectEx = @{@"case_id": @"PING-012", @"prefer_mode": @"IPv4优先"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"PING IPv4优先验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            NSString *hostIP = origin[@"host_ip"];
            XCTAssertNotNil(hostIP, @"host_ip不应为空");
            NSLog(@"📍 IPv4优先模式 - host_ip: %@", hostIP);
            
            // IPv4优先时，应优先返回IPv4地址
            if ([self isIPv4Address:hostIP]) {
                NSLog(@"✅ 返回IPv4地址: %@", hostIP);
            } else if ([self isIPv6Address:hostIP]) {
                NSLog(@"ℹ️ 返回IPv6地址（可能无IPv4）: %@", hostIP);
            }
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【PING-013】验证prefer参数 - IPv6优先 (prefer=1)
- (void)testPingPreferIPv6First {
    NSLog(@"🧪 开始执行用例PING-013：prefer参数验证 - IPv6优先");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-prefer-IPv6优先"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.prefer = 1;  // IPv6优先
    request.detectEx = @{@"case_id": @"PING-013", @"prefer_mode": @"IPv6优先"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"PING IPv6优先验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            NSString *hostIP = origin[@"host_ip"];
            XCTAssertNotNil(hostIP, @"host_ip不应为空");
            NSLog(@"📍 IPv6优先模式 - host_ip: %@", hostIP);
            
            // IPv6优先时，如有IPv6应返回IPv6地址
            if ([self isIPv6Address:hostIP]) {
                NSLog(@"✅ 返回IPv6地址: %@", hostIP);
            } else if ([self isIPv4Address:hostIP]) {
                NSLog(@"ℹ️ 返回IPv4地址（可能无IPv6）: %@", hostIP);
            }
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【PING-014】验证prefer参数 - IPv4 Only (prefer=2)
- (void)testPingPreferIPv4Only {
    NSLog(@"🧪 开始执行用例PING-014：prefer参数验证 - IPv4 Only");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-prefer-IPv4Only"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.prefer = 2;  // IPv4 Only
    request.detectEx = @{@"case_id": @"PING-014", @"prefer_mode": @"IPv4Only"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"PING IPv4 Only验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            NSString *hostIP = origin[@"host_ip"];
            XCTAssertNotNil(hostIP, @"host_ip不应为空");
            NSLog(@"📍 IPv4 Only模式 - host_ip: %@", hostIP);
            
            // IPv4 Only 应该只返回IPv4地址
            XCTAssertTrue([self isIPv4Address:hostIP], @"IPv4 Only模式应返回IPv4地址，实际: %@", hostIP);
            NSLog(@"✅ IPv4 Only验证通过: %@", hostIP);
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【PING-015】验证prefer参数 - IPv6 Only (prefer=3)
- (void)testPingPreferIPv6Only {
    NSLog(@"🧪 开始执行用例PING-015：prefer参数验证 - IPv6 Only");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-prefer-IPv6Only"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = @"www.baidu.com";  // 使用支持IPv6的域名
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.prefer = 3;  // IPv6 Only
    request.detectEx = @{@"case_id": @"PING-015", @"prefer_mode": @"IPv6Only"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"PING IPv6 Only验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            NSString *hostIP = origin[@"host_ip"];
            XCTAssertNotNil(hostIP, @"host_ip不应为空");
            NSLog(@"📍 IPv6 Only模式 - host_ip: %@", hostIP);
            
            // IPv6 Only 应该只返回IPv6地址
            XCTAssertTrue([self isIPv6Address:hostIP], @"IPv6 Only模式应返回IPv6地址，实际: %@", hostIP);
            NSLog(@"✅ IPv6 Only验证通过: %@", hostIP);
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

#pragma mark - 多端口网络环境测试

/// 【PING-009】验证多端口探测 - Wi-Fi和4G网络环境下usedNet字段识别
/// 注意：此测试需要在有Wi-Fi和蜂窝网络的设备上运行，enableMultiplePortsDetect=YES时会触发多次回调
/// 验证点：1. 回调次数=2  2. 必须同时检测到Wi-Fi和4G/蜂窝网络类型
- (void)testPingMultiplePortsWithNetworkType {
    NSLog(@"🧪 开始执行用例PING-009：多端口探测网络环境验证");
    NSLog(@"⚠️ 注意：此测试需要设备同时开启Wi-Fi和蜂窝数据");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-多端口网络环境"];
    
    __block NSMutableArray<NSString *> *detectedNetworks = [NSMutableArray array];
    __block NSMutableArray<NSString *> *detectedInterfaces = [NSMutableArray array];
    __block NSInteger callbackCount = 0;
    __block BOOL expectationFulfilled = NO;
    __block BOOL hasWiFi = NO;
    __block BOOL hasCellular = NO;
    NSInteger expectedCallbackCount = 2;  // 期望2次回调（Wi-Fi + 蜂窝）
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.size = 64;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = YES;  // 启用多端口探测
    request.detectEx = @{@"case_id": @"PING-009", @"test_scene": @"multi_port_network"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        @try {
            callbackCount++;
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:[NSString stringWithFormat:@"PING多端口探测结果 #%ld", (long)callbackCount]];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            NSDictionary *netInfo = [self safeConvertToDictionary:origin[@"netInfo"]];
            
            // 验证netInfo字段存在
            XCTAssertNotNil(netInfo, @"netInfo不应为空");
            
            // 验证usedNet字段
            NSString *usedNet = netInfo[@"usedNet"];
            XCTAssertNotNil(usedNet, @"usedNet字段不应为空");
            NSLog(@"📍 回调#%ld - 使用网络类型(usedNet): %@", (long)callbackCount, usedNet);
            
            // 记录检测到的网络类型
            if (usedNet && ![detectedNetworks containsObject:usedNet]) {
                [detectedNetworks addObject:usedNet];
            }
            
            // 判断网络类型：Wi-Fi 或 蜂窝网络(4G/5G/3G/2G)
            NSString *lowerUsedNet = [usedNet lowercaseString];
            if ([lowerUsedNet containsString:@"wifi"] || [lowerUsedNet containsString:@"wi-fi"]) {
                hasWiFi = YES;
                NSLog(@"📍 回调#%ld - 检测到Wi-Fi网络", (long)callbackCount);
            } else if ([lowerUsedNet containsString:@"4g"] || 
                       [lowerUsedNet containsString:@"5g"] || 
                       [lowerUsedNet containsString:@"3g"] || 
                       [lowerUsedNet containsString:@"2g"] || 
                       [lowerUsedNet containsString:@"cellular"] ||
                       [lowerUsedNet containsString:@"lte"] ||
                       [lowerUsedNet containsString:@"wwan"]) {
                hasCellular = YES;
                NSLog(@"📍 回调#%ld - 检测到蜂窝网络: %@", (long)callbackCount, usedNet);
            }
            
            // 验证interface字段（网络接口）
            NSString *interface = origin[@"interface"];
            if (interface && ![detectedInterfaces containsObject:interface]) {
                [detectedInterfaces addObject:interface];
            }
            NSLog(@"📍 回调#%ld - 网络接口(interface): %@", (long)callbackCount, interface);
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        }
        
        // 收到预期回调数后立即完成测试
        if (callbackCount >= expectedCallbackCount && !expectationFulfilled) {
            expectationFulfilled = YES;
            
            NSLog(@"📊 PING多端口探测结果汇总:");
            NSLog(@"   - 总回调次数: %ld (期望: %ld)", (long)callbackCount, (long)expectedCallbackCount);
            NSLog(@"   - 检测到的网络类型: %@", detectedNetworks);
            NSLog(@"   - 检测到的网络接口: %@", detectedInterfaces);
            NSLog(@"   - Wi-Fi: %@, 蜂窝: %@", hasWiFi ? @"✅" : @"❌", hasCellular ? @"✅" : @"❌");
            
            // 核心断言：必须同时检测到Wi-Fi和蜂窝网络
            XCTAssertEqual(callbackCount, expectedCallbackCount, 
                          @"多网卡探测应产生%ld次回调，实际: %ld", (long)expectedCallbackCount, (long)callbackCount);
            XCTAssertTrue(hasWiFi, @"多网卡探测应检测到Wi-Fi网络，实际检测到: %@", detectedNetworks);
            XCTAssertTrue(hasCellular, @"多网卡探测应检测到蜂窝网络(4G/5G等)，实际检测到: %@", detectedNetworks);
            XCTAssertEqual(detectedInterfaces.count, 2, 
                          @"应检测到2个不同的网络接口，实际: %@", detectedInterfaces);
            
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:^(NSError *error) {
        if (error) {
            NSLog(@"❌ 测试超时 - 总回调次数: %ld (期望: %ld)", (long)callbackCount, (long)expectedCallbackCount);
            NSLog(@"   - 检测到网络类型: %@", detectedNetworks);
            NSLog(@"   - Wi-Fi: %@, 蜂窝: %@", hasWiFi ? @"✅" : @"❌", hasCellular ? @"✅" : @"❌");
        }
    }];
}

/// 【PING-010】验证当前网络环境识别（单端口）
- (void)testPingCurrentNetworkIdentification {
    NSLog(@"🧪 开始执行用例PING-010：当前网络环境识别");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-网络识别"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.enableMultiplePortsDetect = NO;  // 单端口探测
    request.detectEx = @{@"case_id": @"PING-010", @"test_scene": @"network_identification"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"PING当前网络环境识别结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            NSDictionary *netInfo = [self safeConvertToDictionary:origin[@"netInfo"]];
            
            // 完整验证netInfo字段
            [self validateNetInfo:netInfo];
            
            // 详细打印网络信息
            NSLog(@"📍 网络环境详情:");
            NSLog(@"   - usedNet (使用网络): %@", netInfo[@"usedNet"]);
            NSLog(@"   - defaultNet (默认网络): %@", netInfo[@"defaultNet"]);
            NSLog(@"   - dns: %@", netInfo[@"dns"]);
            NSLog(@"   - client_ip: %@", netInfo[@"client_ip"]);
            NSLog(@"   - isp_en (运营商): %@", netInfo[@"isp_en"]);
            NSLog(@"   - province_en: %@", netInfo[@"province_en"]);
            NSLog(@"   - city_en: %@", netInfo[@"city_en"]);
            
            // 验证usedNet和defaultNet的一致性（单端口模式下应该一致）
            NSString *usedNet = netInfo[@"usedNet"];
            NSString *defaultNet = netInfo[@"defaultNet"];
            XCTAssertNotNil(usedNet, @"usedNet不应为空");
            XCTAssertNotNil(defaultNet, @"defaultNet不应为空");
            
            // 单端口模式下，usedNet应该和defaultNet表示同一种网络类型
            // 注意：可能存在格式差异，如 "wifi" vs "Wi-Fi"，需要标准化比较
            NSString *normalizedUsedNet = [[usedNet lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
            NSString *normalizedDefaultNet = [[defaultNet lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
            XCTAssertTrue([normalizedUsedNet isEqualToString:normalizedDefaultNet], 
                         @"单端口模式下usedNet应等于defaultNet，usedNet=%@, defaultNet=%@", usedNet, defaultNet);
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【PING-011】验证多端口探测产生多个网络类型结果
/// 注意：需要设备同时连接Wi-Fi和蜂窝数据才能检测到多种网络类型
/// 验证点：必须同时检测到Wi-Fi和蜂窝网络(4G/5G等)
- (void)testPingMultipleNetworkTypesDetection {
    NSLog(@"🧪 开始执行用例PING-011：多网络类型探测");
    NSLog(@"⚠️ 注意：此测试需要设备同时开启Wi-Fi和蜂窝数据");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"PING-多网络类型"];
    
    __block NSMutableSet<NSString *> *networkTypes = [NSMutableSet set];
    __block NSMutableSet<NSString *> *interfaces = [NSMutableSet set];
    __block NSInteger callbackCount = 0;
    __block BOOL expectationFulfilled = NO;
    __block BOOL hasWiFi = NO;
    __block BOOL hasCellular = NO;
    NSInteger expectedCallbackCount = 2;
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.enableMultiplePortsDetect = YES;
    request.detectEx = @{@"case_id": @"PING-011", @"test_scene": @"multi_network_types"};
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        @try {
            callbackCount++;
            NSDictionary *data = [self parseResponseContent:response];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            NSDictionary *netInfo = [self safeConvertToDictionary:origin[@"netInfo"]];
            
            NSString *usedNet = netInfo[@"usedNet"];
            NSString *interface = origin[@"interface"];
            
            if (usedNet) {
                [networkTypes addObject:usedNet];
                
                // 判断网络类型
                NSString *lowerUsedNet = [usedNet lowercaseString];
                if ([lowerUsedNet containsString:@"wifi"] || [lowerUsedNet containsString:@"wi-fi"]) {
                    hasWiFi = YES;
                } else if ([lowerUsedNet containsString:@"4g"] || 
                           [lowerUsedNet containsString:@"5g"] || 
                           [lowerUsedNet containsString:@"3g"] || 
                           [lowerUsedNet containsString:@"2g"] || 
                           [lowerUsedNet containsString:@"cellular"] ||
                           [lowerUsedNet containsString:@"lte"] ||
                           [lowerUsedNet containsString:@"wwan"]) {
                    hasCellular = YES;
                }
            }
            if (interface) {
                [interfaces addObject:interface];
            }
            
            NSLog(@"📍 回调#%ld - usedNet: %@, interface: %@", (long)callbackCount, usedNet, interface);
            
        } @catch (NSException *exception) {
            NSLog(@"⚠️ 回调#%ld 处理异常: %@", (long)callbackCount, exception.reason);
        }
        
        // 收到预期回调数后立即完成测试
        if (callbackCount >= expectedCallbackCount && !expectationFulfilled) {
            expectationFulfilled = YES;
            
            NSLog(@"📊 多网络类型探测结果:");
            NSLog(@"   - 总回调次数: %ld", (long)callbackCount);
            NSLog(@"   - 检测到的网络类型: %@", networkTypes);
            NSLog(@"   - 检测到的网络接口: %@", interfaces);
            NSLog(@"   - Wi-Fi: %@, 蜂窝: %@", hasWiFi ? @"✅" : @"❌", hasCellular ? @"✅" : @"❌");
            
            // 核心断言
            XCTAssertEqual(networkTypes.count, 2, @"应检测到2种网络类型(Wi-Fi和蜂窝)，实际: %@", networkTypes);
            XCTAssertTrue(hasWiFi, @"应检测到Wi-Fi网络，实际检测到: %@", networkTypes);
            XCTAssertTrue(hasCellular, @"应检测到蜂窝网络(4G/5G等)，实际检测到: %@", networkTypes);
            XCTAssertEqual(interfaces.count, 2, @"应检测到2个不同的网络接口，实际: %@", interfaces);
            
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:^(NSError *error) {
        if (error) {
            NSLog(@"❌ 测试超时 - Wi-Fi: %@, 蜂窝: %@", hasWiFi ? @"✅" : @"❌", hasCellular ? @"✅" : @"❌");
        }
    }];
}

#pragma mark - 多协议并发探测测试

/// 【PING-016】验证多协议并发探测 - 同时发起PING、HTTP、TCPPING、DNS探测
/// 验证点：1. 所有探测类型均成功返回  2. 数据上报完整性  3. 各协议字段准确性  4. userEx全局字段正确传递
- (void)testMultiProtocolConcurrentDetection {
    NSLog(@"🧪 开始执行用例PING-016：多协议并发探测验证");
    NSLog(@"📋 同时发起 PING、HTTP、TCPPING、DNS 四种探测");
    
    // 创建4个期望，每种协议一个
    XCTestExpectation *pingExpectation = [self expectationWithDescription:@"PING探测完成"];
    XCTestExpectation *httpExpectation = [self expectationWithDescription:@"HTTP探测完成"];
    XCTestExpectation *tcpExpectation = [self expectationWithDescription:@"TCPPING探测完成"];
    XCTestExpectation *dnsExpectation = [self expectationWithDescription:@"DNS探测完成"];
    
    // 防止多次fulfill的标志位
    __block BOOL pingFulfilled = NO;
    __block BOOL httpFulfilled = NO;
    __block BOOL tcpFulfilled = NO;
    __block BOOL dnsFulfilled = NO;
    
    // 记录各协议探测结果
    __block NSDictionary *pingResult = nil;
    __block NSDictionary *httpResult = nil;
    __block NSDictionary *tcpResult = nil;
    __block NSDictionary *dnsResult = nil;
    
    __block NSError *pingError = nil;
    __block NSError *httpError = nil;
    __block NSError *tcpError = nil;
    __block NSError *dnsError = nil;
    
    // ===== 1. 发起 PING 探测 =====
    CLSPingRequest *pingRequest = [[CLSPingRequest alloc] init];
    pingRequest.domain = kTestDomain;
    pingRequest.appKey = kTestAppKey;
    pingRequest.maxTimes = 3;
    pingRequest.size = 64;
    pingRequest.timeout = 10000;  // 10秒，单位ms
    pingRequest.detectEx = @{@"case_id": @"PING-016", @"protocol": @"ping", @"test_scene": @"concurrent"};
    
    [self.diagnosis pingv2:pingRequest complate:^(CLSResponse *response) {
        @synchronized (pingExpectation) {
            if (pingFulfilled) return;
            pingFulfilled = YES;
        }
        @try {
            pingResult = [self parseResponseContent:response];
            NSLog(@"✅ PING探测完成");
        } @catch (NSException *exception) {
            pingError = [NSError errorWithDomain:@"PingError" code:-1 userInfo:@{NSLocalizedDescriptionKey: exception.reason}];
            NSLog(@"❌ PING探测异常: %@", exception.reason);
        } @finally {
            [pingExpectation fulfill];
        }
    }];
    
    // ===== 2. 发起 HTTP 探测 =====
    CLSHttpRequest *httpRequest = [[CLSHttpRequest alloc] init];
    httpRequest.domain = @"https://www.tencent.com";
    httpRequest.appKey = kTestAppKey;
    httpRequest.timeout = 15000;  // 15秒，单位ms
    httpRequest.detectEx = @{@"case_id": @"PING-016", @"protocol": @"http", @"test_scene": @"concurrent"};
    
    [self.diagnosis httpingv2:httpRequest complate:^(CLSResponse *response) {
        @synchronized (httpExpectation) {
            if (httpFulfilled) return;
            httpFulfilled = YES;
        }
        @try {
            httpResult = [self parseResponseContent:response];
            NSLog(@"✅ HTTP探测完成");
        } @catch (NSException *exception) {
            httpError = [NSError errorWithDomain:@"HttpError" code:-1 userInfo:@{NSLocalizedDescriptionKey: exception.reason}];
            NSLog(@"❌ HTTP探测异常: %@", exception.reason);
        } @finally {
            [httpExpectation fulfill];
        }
    }];
    
    // ===== 3. 发起 TCPPING 探测 =====
    CLSTcpRequest *tcpRequest = [[CLSTcpRequest alloc] init];
    tcpRequest.domain = kTestDomain;
    tcpRequest.port = 443;
    tcpRequest.appKey = kTestAppKey;
    tcpRequest.maxTimes = 3;
    tcpRequest.timeout = 10000;  // 10秒，单位ms
    tcpRequest.detectEx = @{@"case_id": @"PING-016", @"protocol": @"tcpping", @"test_scene": @"concurrent"};
    
    [self.diagnosis tcpPingv2:tcpRequest complate:^(CLSResponse *response) {
        @synchronized (tcpExpectation) {
            if (tcpFulfilled) return;
            tcpFulfilled = YES;
        }
        @try {
            tcpResult = [self parseResponseContent:response];
            NSLog(@"✅ TCPPING探测完成");
        } @catch (NSException *exception) {
            tcpError = [NSError errorWithDomain:@"TcpError" code:-1 userInfo:@{NSLocalizedDescriptionKey: exception.reason}];
            NSLog(@"❌ TCPPING探测异常: %@", exception.reason);
        } @finally {
            [tcpExpectation fulfill];
        }
    }];
    
    // ===== 4. 发起 DNS 探测 =====
    CLSDnsRequest *dnsRequest = [[CLSDnsRequest alloc] init];
    dnsRequest.domain = kTestDomain;
    dnsRequest.nameServer = @"114.114.114.114";
    dnsRequest.appKey = kTestAppKey;
    dnsRequest.timeout = 10000;  // 10秒，单位ms
    dnsRequest.detectEx = @{@"case_id": @"PING-016", @"protocol": @"dns", @"test_scene": @"concurrent"};
    
    [self.diagnosis dns:dnsRequest complate:^(CLSResponse *response) {
        @synchronized (dnsExpectation) {
            if (dnsFulfilled) return;
            dnsFulfilled = YES;
        }
        @try {
            dnsResult = [self parseResponseContent:response];
            NSLog(@"✅ DNS探测完成");
        } @catch (NSException *exception) {
            dnsError = [NSError errorWithDomain:@"DnsError" code:-1 userInfo:@{NSLocalizedDescriptionKey: exception.reason}];
            NSLog(@"❌ DNS探测异常: %@", exception.reason);
        } @finally {
            [dnsExpectation fulfill];
        }
    }];
    
    // ===== 等待所有探测完成 =====
    [self waitForExpectationsWithTimeout:60 handler:^(NSError *error) {
        if (error) {
            NSLog(@"❌ 并发探测超时: %@", error.localizedDescription);
        }
    }];
    
    // ===== 验证所有探测结果 =====
    NSLog(@"📊 ========== 多协议并发探测结果汇总 ==========");
    
    // 获取全局 userEx 用于验证
    NSDictionary *globalUserEx = [[ClsNetworkDiagnosis sharedInstance] getUserEx];
    NSLog(@"📋 全局 userEx: %@", globalUserEx);
    
    // ----- PING 结果验证 -----
    XCTAssertNil(pingError, @"PING探测不应出错: %@", pingError);
    XCTAssertNotNil(pingResult, @"PING结果不应为空");
    if (pingResult) {
        [self logKeyResult:pingResult withTitle:@"PING探测结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:pingResult[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(attribute[@"net.type"], @"ping", @"PING net.type应为ping");
        XCTAssertEqualObjects(origin[@"method"], @"ping", @"PING method应为ping");
        XCTAssertNotNil(origin[@"host_ip"], @"PING host_ip不应为空");
        XCTAssertNotNil(origin[@"latency"], @"PING latency不应为空");
        
        // 验证 userEx
        NSDictionary *userEx = [self safeConvertToDictionary:origin[@"userEx"]];
        for (NSString *key in globalUserEx) {
            XCTAssertEqualObjects(userEx[key], globalUserEx[key], @"PING userEx.%@ 不匹配", key);
        }
        NSLog(@"   ✅ PING探测验证通过");
    }
    
    // ----- HTTP 结果验证 -----
    XCTAssertNil(httpError, @"HTTP探测不应出错: %@", httpError);
    XCTAssertNotNil(httpResult, @"HTTP结果不应为空");
    if (httpResult) {
        [self logKeyResult:httpResult withTitle:@"HTTP探测结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:httpResult[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(attribute[@"net.type"], @"http", @"HTTP net.type应为http");
        XCTAssertEqualObjects(origin[@"method"], @"http", @"HTTP method应为http");
        XCTAssertNotNil(origin[@"httpCode"], @"HTTP httpCode不应为空");
        XCTAssertNotNil(origin[@"requestTime"], @"HTTP requestTime不应为空");
        
        // 验证 userEx
        NSDictionary *userEx = [self safeConvertToDictionary:origin[@"userEx"]];
        for (NSString *key in globalUserEx) {
            XCTAssertEqualObjects(userEx[key], globalUserEx[key], @"HTTP userEx.%@ 不匹配", key);
        }
        NSLog(@"   ✅ HTTP探测验证通过");
    }
    
    // ----- TCPPING 结果验证 -----
    XCTAssertNil(tcpError, @"TCPPING探测不应出错: %@", tcpError);
    XCTAssertNotNil(tcpResult, @"TCPPING结果不应为空");
    if (tcpResult) {
        [self logKeyResult:tcpResult withTitle:@"TCPPING探测结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:tcpResult[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(attribute[@"net.type"], @"tcpping", @"TCPPING net.type应为tcpping");
        XCTAssertEqualObjects(origin[@"method"], @"tcpping", @"TCPPING method应为tcpping");
        XCTAssertNotNil(origin[@"host_ip"], @"TCPPING host_ip不应为空");
        XCTAssertEqual([origin[@"port"] integerValue], 443, @"TCPPING port应为443");
        
        // 验证 userEx
        NSDictionary *userEx = [self safeConvertToDictionary:origin[@"userEx"]];
        for (NSString *key in globalUserEx) {
            XCTAssertEqualObjects(userEx[key], globalUserEx[key], @"TCPPING userEx.%@ 不匹配", key);
        }
        NSLog(@"   ✅ TCPPING探测验证通过");
    }
    
    // ----- DNS 结果验证 -----
    XCTAssertNil(dnsError, @"DNS探测不应出错: %@", dnsError);
    XCTAssertNotNil(dnsResult, @"DNS结果不应为空");
    if (dnsResult) {
        [self logKeyResult:dnsResult withTitle:@"DNS探测结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:dnsResult[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 验证基础字段
        XCTAssertEqualObjects(attribute[@"net.type"], @"dns", @"DNS net.type应为dns");
        XCTAssertEqualObjects(origin[@"method"], @"dns", @"DNS method应为dns");
        XCTAssertNotNil(origin[@"status"], @"DNS status不应为空");
        XCTAssertNotNil(origin[@"latency"], @"DNS latency不应为空");
        
        // 验证 userEx
        NSDictionary *userEx = [self safeConvertToDictionary:origin[@"userEx"]];
        for (NSString *key in globalUserEx) {
            XCTAssertEqualObjects(userEx[key], globalUserEx[key], @"DNS userEx.%@ 不匹配", key);
        }
        NSLog(@"   ✅ DNS探测验证通过");
    }
    
    // ----- 汇总验证 -----
    NSInteger successCount = 0;
    if (pingResult && !pingError) successCount++;
    if (httpResult && !httpError) successCount++;
    if (tcpResult && !tcpError) successCount++;
    if (dnsResult && !dnsError) successCount++;
    
    NSLog(@"📊 多协议并发探测完成: %ld/4 成功", (long)successCount);
    XCTAssertEqual(successCount, 4, @"所有4种协议探测都应成功完成");
    
    NSLog(@"✅ 多协议并发探测测试通过！");
}

/// 【PING-017】验证多协议并发探测 - 包含MTR的完整五协议测试
/// 验证点：同时发起PING、HTTP、TCPPING、DNS、MTR五种探测
- (void)testFullProtocolConcurrentDetection {
    NSLog(@"🧪 开始执行用例PING-017：完整五协议并发探测验证");
    NSLog(@"📋 同时发起 PING、HTTP、TCPPING、DNS、MTR 五种探测");
    
    // 创建5个期望
    XCTestExpectation *pingExpectation = [self expectationWithDescription:@"PING探测完成"];
    XCTestExpectation *httpExpectation = [self expectationWithDescription:@"HTTP探测完成"];
    XCTestExpectation *tcpExpectation = [self expectationWithDescription:@"TCPPING探测完成"];
    XCTestExpectation *dnsExpectation = [self expectationWithDescription:@"DNS探测完成"];
    XCTestExpectation *mtrExpectation = [self expectationWithDescription:@"MTR探测完成"];
    
    // 防止多次fulfill的标志位
    __block BOOL pingFulfilled = NO;
    __block BOOL httpFulfilled = NO;
    __block BOOL tcpFulfilled = NO;
    __block BOOL dnsFulfilled = NO;
    __block BOOL mtrFulfilled = NO;
    
    __block NSMutableDictionary<NSString *, NSDictionary *> *results = [NSMutableDictionary dictionary];
    __block NSMutableDictionary<NSString *, NSError *> *errors = [NSMutableDictionary dictionary];
    
    // ===== 1. PING 探测 =====
    CLSPingRequest *pingRequest = [[CLSPingRequest alloc] init];
    pingRequest.domain = kTestDomain;
    pingRequest.appKey = kTestAppKey;
    pingRequest.maxTimes = 3;
    pingRequest.detectEx = @{@"case_id": @"PING-017", @"protocol": @"ping"};
    
    [self.diagnosis pingv2:pingRequest complate:^(CLSResponse *response) {
        @synchronized (pingExpectation) {
            if (pingFulfilled) return;
            pingFulfilled = YES;
        }
        @try {
            results[@"ping"] = [self parseResponseContent:response];
            NSLog(@"✅ PING完成");
        } @catch (NSException *e) {
            errors[@"ping"] = [NSError errorWithDomain:@"Test" code:-1 userInfo:@{NSLocalizedDescriptionKey: e.reason}];
        } @finally {
            [pingExpectation fulfill];
        }
    }];
    
    // ===== 2. HTTP 探测 =====
    CLSHttpRequest *httpRequest = [[CLSHttpRequest alloc] init];
    httpRequest.domain = @"https://www.tencent.com";
    httpRequest.appKey = kTestAppKey;
    httpRequest.timeout = 15000;  // 15秒，单位ms
    httpRequest.detectEx = @{@"case_id": @"PING-017", @"protocol": @"http"};
    
    [self.diagnosis httpingv2:httpRequest complate:^(CLSResponse *response) {
        @synchronized (httpExpectation) {
            if (httpFulfilled) return;
            httpFulfilled = YES;
        }
        @try {
            results[@"http"] = [self parseResponseContent:response];
            NSLog(@"✅ HTTP完成");
        } @catch (NSException *e) {
            errors[@"http"] = [NSError errorWithDomain:@"Test" code:-1 userInfo:@{NSLocalizedDescriptionKey: e.reason}];
        } @finally {
            [httpExpectation fulfill];
        }
    }];
    
    // ===== 3. TCPPING 探测 =====
    CLSTcpRequest *tcpRequest = [[CLSTcpRequest alloc] init];
    tcpRequest.domain = kTestDomain;
    tcpRequest.port = 443;
    tcpRequest.appKey = kTestAppKey;
    tcpRequest.maxTimes = 3;
    tcpRequest.detectEx = @{@"case_id": @"PING-017", @"protocol": @"tcpping"};
    
    [self.diagnosis tcpPingv2:tcpRequest complate:^(CLSResponse *response) {
        @synchronized (tcpExpectation) {
            if (tcpFulfilled) return;
            tcpFulfilled = YES;
        }
        @try {
            results[@"tcpping"] = [self parseResponseContent:response];
            NSLog(@"✅ TCPPING完成");
        } @catch (NSException *e) {
            errors[@"tcpping"] = [NSError errorWithDomain:@"Test" code:-1 userInfo:@{NSLocalizedDescriptionKey: e.reason}];
        } @finally {
            [tcpExpectation fulfill];
        }
    }];
    
    // ===== 4. DNS 探测 =====
    CLSDnsRequest *dnsRequest = [[CLSDnsRequest alloc] init];
    dnsRequest.domain = kTestDomain;
    dnsRequest.nameServer = @"114.114.114.114";
    dnsRequest.appKey = kTestAppKey;
    dnsRequest.detectEx = @{@"case_id": @"PING-017", @"protocol": @"dns"};
    
    [self.diagnosis dns:dnsRequest complate:^(CLSResponse *response) {
        @synchronized (dnsExpectation) {
            if (dnsFulfilled) return;
            dnsFulfilled = YES;
        }
        @try {
            results[@"dns"] = [self parseResponseContent:response];
            NSLog(@"✅ DNS完成");
        } @catch (NSException *e) {
            errors[@"dns"] = [NSError errorWithDomain:@"Test" code:-1 userInfo:@{NSLocalizedDescriptionKey: e.reason}];
        } @finally {
            [dnsExpectation fulfill];
        }
    }];
    
    // ===== 5. MTR 探测 =====
    CLSMtrRequest *mtrRequest = [[CLSMtrRequest alloc] init];
    mtrRequest.domain = kTestDomain;
    mtrRequest.appKey = kTestAppKey;
    mtrRequest.maxTimes = 2;
    mtrRequest.maxTTL = 10;
    mtrRequest.timeout = 30000;  // 30秒，单位ms
    mtrRequest.detectEx = @{@"case_id": @"PING-017", @"protocol": @"mtr"};
    
    [self.diagnosis mtr:mtrRequest complate:^(CLSResponse *response) {
        @synchronized (mtrExpectation) {
            if (mtrFulfilled) return;
            mtrFulfilled = YES;
        }
        @try {
            results[@"mtr"] = [self parseResponseContent:response];
            NSLog(@"✅ MTR完成");
        } @catch (NSException *e) {
            errors[@"mtr"] = [NSError errorWithDomain:@"Test" code:-1 userInfo:@{NSLocalizedDescriptionKey: e.reason}];
        } @finally {
            [mtrExpectation fulfill];
        }
    }];
    
    // ===== 等待所有探测完成 =====
    [self waitForExpectationsWithTimeout:90 handler:nil];
    
    // ===== 验证结果 =====
    NSLog(@"📊 ========== 五协议并发探测结果汇总 ==========");
    
    NSDictionary *globalUserEx = [[ClsNetworkDiagnosis sharedInstance] getUserEx];
    NSArray *protocols = @[@"ping", @"http", @"tcpping", @"dns", @"mtr"];
    NSInteger successCount = 0;
    
    for (NSString *protocol in protocols) {
        NSDictionary *result = results[protocol];
        NSError *error = errors[protocol];
        
        XCTAssertNil(error, @"%@ 探测不应出错: %@", protocol.uppercaseString, error);
        XCTAssertNotNil(result, @"%@ 结果不应为空", protocol.uppercaseString);
        
        if (result && !error) {
            successCount++;
            
            NSDictionary *attribute = [self safeConvertToDictionary:result[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 验证 net.type (mtr的net.type就是mtr)
            XCTAssertEqualObjects(attribute[@"net.type"], protocol, @"%@ net.type应为%@", protocol.uppercaseString, protocol);
            
            // 验证 userEx
            NSDictionary *userEx = [self safeConvertToDictionary:origin[@"userEx"]];
            for (NSString *key in globalUserEx) {
                XCTAssertEqualObjects(userEx[key], globalUserEx[key], @"%@ userEx.%@ 不匹配", protocol.uppercaseString, key);
            }
            
            NSLog(@"   ✅ %@ 验证通过", protocol.uppercaseString);
        }
    }
    
    NSLog(@"📊 五协议并发探测完成: %ld/5 成功", (long)successCount);
    XCTAssertEqual(successCount, 5, @"所有5种协议探测都应成功完成");
    
    NSLog(@"✅ 完整五协议并发探测测试通过！");
}

@end
