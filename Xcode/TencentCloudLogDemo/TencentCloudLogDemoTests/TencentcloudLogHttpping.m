#import "CLSNetworkDiagnosisBaseTests.h"

@interface CLSNetworkHttppingTests : CLSNetworkDiagnosisBaseTests
@end

@implementation CLSNetworkHttppingTests

#pragma mark - 基本功能测试

/// 【HTTP-001】验证HTTP探测基本功能及所有字段完整性
- (void)testHttpBasicFunctionality {
    NSLog(@"🧪 开始执行用例HTTP-001：HTTP探测基本功能验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP基本功能"];
    __block BOOL fulfilled = NO;
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"http://www.baidu.com";
    request.appKey = kTestAppKey;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableSSLVerification = true;
    request.enableMultiplePortsDetect = NO;  // 基本测试使用单网卡模式
    request.pageName = @"http_test_page";
    request.detectEx = @{@"case_id": @"HTTP-001", @"priority": @"P0"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"HTTP基本功能验证结果"];
            
            // 1. 公共字段校验
            [self validateCommonFields:data];
            [self validateResourceFields:data];
            [self validateAttributeFields:data expectedType:@"http"];
            [self validateNetOriginFields:data expectedMethod:@"http"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 2. HTTP专用字段校验
            [self validateHttpOriginFields:origin];
            [self validateHttpTimeFields:origin];
            
            // 3. HTTP headers和desc字段校验
            [self validateHttpHeadersFields:data];
            [self validateHttpDescFields:data];
            
            // 4. 网络环境信息校验
            [self validateNetInfo:[self safeConvertToDictionary:origin[@"netInfo"]]];
            
            // 5. 扩展字段校验
            [self validateExtensionFields:origin 
                         expectedDetectEx:@{@"case_id": @"HTTP-001"}];
            
            // 6. 全局 userEx 字段校验（验证 setUserEx 设置成功）
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

/// 【HTTP-002】验证domain参数 - HTTPS
- (void)testHttpDomainHttps {
    NSLog(@"🧪 开始执行用例HTTP-002：domain参数验证 - HTTPS");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP-domain-https"];
    __block BOOL fulfilled = NO;
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://www.baidu.com";
    request.appKey = kTestAppKey;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"HTTP-002"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"HTTP HTTPS验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertTrue([origin[@"url"] hasPrefix:@"https://"], @"url应以https://开头");
            XCTAssertNotNil(origin[@"sslTime"], @"HTTPS应有sslTime");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【HTTP-003】验证domain参数 - HTTP
- (void)testHttpDomainHttp {
    NSLog(@"🧪 开始执行用例HTTP-003：domain参数验证 - HTTP");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP-domain-http"];
    __block BOOL fulfilled = NO;
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"http://www.baidu.com";
    request.appKey = kTestAppKey;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = NO;
    request.enableSSLVerification = FALSE;
    request.detectEx = @{@"case_id": @"HTTP-003"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"HTTP HTTP验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertNotNil(origin[@"url"], @"url不应为空");
            XCTAssertNotNil(origin[@"httpCode"], @"httpCode不应为空");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【HTTP-004】验证timeout参数
- (void)testHttpTimeoutParameter {
    NSLog(@"🧪 开始执行用例HTTP-004：timeout参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP-timeout"];
    __block BOOL fulfilled = NO;
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://192.0.2.1:443";  // 不可达IP
    request.appKey = kTestAppKey;
    request.timeout = 2000;  // 2秒超时，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"HTTP-004"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"HTTP timeout验证结果"];
            
            // 超时也应返回数据
            XCTAssertNotNil(data, @"超时也应返回数据");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:15 handler:nil];
}

/// 【HTTP-005】验证enableSSLVerification参数 - 开启
- (void)testHttpEnableSSLVerificationOn {
    NSLog(@"🧪 开始执行用例HTTP-005：enableSSLVerification参数验证 - 开启");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP-ssl-on"];
    __block BOOL fulfilled = NO;
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://www.tencentcloud.com";
    request.appKey = kTestAppKey;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableSSLVerification = YES;
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"HTTP-005"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"HTTP SSL验证开启结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 有效证书应该成功
            XCTAssertEqual([origin[@"httpCode"] integerValue], 200, @"有效证书应返回200");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【HTTP-006】验证enableMultiplePortsDetect参数
- (void)testHttpEnableMultiplePortsDetect {
    NSLog(@"🧪 开始执行用例HTTP-006：enableMultiplePortsDetect参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP-multiPorts"];
    __block BOOL fulfilled = NO;
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://www.baidu.com";
    request.appKey = kTestAppKey;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = YES;
    request.detectEx = @{@"case_id": @"HTTP-006"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"HTTP multiPorts验证结果"];
            
            [self validateCommonFields:data];
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【HTTP-007】验证detectEx扩展字段
- (void)testHttpExtensionFields {
    NSLog(@"🧪 开始执行用例HTTP-007：扩展字段验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP-extension"];
    __block BOOL fulfilled = NO;
    
    NSDictionary *detectEx = @{
        @"case_id": @"HTTP-007",
        @"http_scene": @"api_call",
        @"priority": @"P1"
    };
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://www.tencentcloud.com";
    request.appKey = kTestAppKey;
    request.timeout = 10000;  // 10秒，单位ms
    request.pageName = @"http_test_page";
    request.enableMultiplePortsDetect = NO;
    request.detectEx = detectEx;
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"HTTP扩展字段验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertEqualObjects(attribute[@"page.name"], @"http_test_page", @"page.name应匹配");
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

/// 【HTTP-008】验证所有返回字段完整性
- (void)testHttpAllFieldsCompleteness {
    NSLog(@"🧪 开始执行用例HTTP-008：字段完整性验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP-字段完整性"];
    __block BOOL fulfilled = NO;
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://www.tencentcloud.com";
    request.appKey = kTestAppKey;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableSSLVerification = YES;
    request.enableMultiplePortsDetect = NO;
    request.pageName = @"http_fields_test";
    request.detectEx = @{@"case_id": @"HTTP-008"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"HTTP字段完整性验证结果"];
            
            // 1. 公共字段
            [self validateCommonFields:data];
            [self validateResourceFields:data];
            
            // 2. Attribute字段
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            XCTAssertEqualObjects(attribute[@"net.type"], @"http", @"net.type应为http");
            
            // 3. net.origin字段
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            [self validateHttpOriginFields:origin];
            
            // 4. 验证src字段
            XCTAssertEqualObjects(origin[@"src"], @"app", @"src应为app");
            
            // 5. headers字段
            [self validateHttpHeadersFields:data];
            
            // 6. desc字段（HTTP请求生命周期时间点）
            [self validateHttpDescFields:data];
            
            // 7. netInfo字段
            [self validateNetInfo:[self safeConvertToDictionary:origin[@"netInfo"]]];
            
            // 8. 验证HTTP特有字段
            XCTAssertNotNil(origin[@"httpCode"], @"应包含httpCode");
            XCTAssertNotNil(origin[@"httpProtocol"], @"应包含httpProtocol");
            XCTAssertNotNil(origin[@"sendBytes"], @"应包含sendBytes");
            XCTAssertNotNil(origin[@"receiveBytes"], @"应包含receiveBytes");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【HTTP-009】验证HTTP时间字段逻辑
- (void)testHttpTimeFieldsLogic {
    NSLog(@"🧪 开始执行用例HTTP-009：时间字段逻辑验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP-时间逻辑"];
    __block BOOL fulfilled = NO;
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://www.baidu.com";
    request.appKey = kTestAppKey;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"HTTP-009"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"HTTP时间字段逻辑验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 验证时间字段为非负数
            [self validateHttpTimeFields:origin];
            
            // 验证requestTime应为各阶段时间之和（允许误差）
            double dnsTime = [origin[@"dnsTime"] doubleValue];
            double tcpTime = [origin[@"tcpTime"] doubleValue];
            double sslTime = [origin[@"sslTime"] doubleValue];
            double requestTime = [origin[@"requestTime"] doubleValue];
            
            NSLog(@"📍 时间字段: dnsTime=%.2f, tcpTime=%.2f, sslTime=%.2f, requestTime=%.2f", 
                  dnsTime, tcpTime, sslTime, requestTime);
            
            XCTAssertGreaterThan(requestTime, 0, @"requestTime应大于0");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

#pragma mark - 异常场景测试

/// 【HTTP-ERR-001】异常场景 - 404错误
- (void)testHttp404Error {
    NSLog(@"🧪 开始执行用例HTTP-ERR-001：404错误");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP 404 错误"];
    __block BOOL fulfilled = NO;
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://www.tencentcloud.com/404-page-not-exist";
    request.appKey = kTestAppKey;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"HTTP-ERR-001"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"HTTP 404错误结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertEqual([origin[@"httpCode"] integerValue], 404, @"应返回404");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【HTTP-ERR-002】异常场景 - 连接超时
- (void)testHttpConnectionTimeout {
    NSLog(@"🧪 开始执行用例HTTP-ERR-002：连接超时");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP 连接超时"];
    __block BOOL fulfilled = NO;
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://192.0.2.1:443";  // 不可达IP
    request.appKey = kTestAppKey;
    request.timeout = 3000;  // 3秒，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"HTTP-ERR-002"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"HTTP连接超时结果"];
            
            // 超时也应返回数据
            XCTAssertNotNil(data, @"超时也应返回数据");
            
            // 校验错误信息
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            NSString *errorMessage = origin[@"errMsg"];
            XCTAssertNotNil(errorMessage, @"超时应包含errMsg");
            XCTAssertTrue([errorMessage containsString:@"timed out"] || [errorMessage containsString:@"timeout"],
                         @"error_message应包含超时信息，实际值: %@", errorMessage);
            NSLog(@"📍 错误信息: %@", errorMessage);
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:15 handler:nil];
}

/// 【HTTP-ERR-003】异常场景 - 无效域名
- (void)testHttpInvalidDomain {
    NSLog(@"🧪 开始执行用例HTTP-ERR-003：无效域名");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP无效域名"];
    __block BOOL fulfilled = NO;
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://invalid.domain.not.exist.test";
    request.appKey = kTestAppKey;
    request.timeout = 5000;  // 5秒，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"HTTP-ERR-003"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"HTTP无效域名结果"];
            
            XCTAssertNotNil(data, @"无效域名也应有返回数据");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:15 handler:nil];
}

#pragma mark - 多网卡环境测试

/// 【HTTP-010】验证多网卡探测 - Wi-Fi和蜂窝网络环境下的完整行为
/// 注意：此测试需要在同时连接Wi-Fi和蜂窝网络的设备上运行
/// 验证点：1. 回调次数=2  2. 必须同时检测到Wi-Fi和4G/蜂窝网络类型
- (void)testHttpMultiplePortsWithNetworkType {
    NSLog(@"🧪 开始执行用例HTTP-010：多网卡探测网络环境验证");
    NSLog(@"⚠️ 注意：此测试需要设备同时开启Wi-Fi和蜂窝数据");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP-多网卡网络环境"];
    
    __block NSMutableArray<NSString *> *detectedNetworks = [NSMutableArray array];
    __block NSMutableArray<NSString *> *detectedInterfaces = [NSMutableArray array];
    __block NSInteger callbackCount = 0;
    __block BOOL expectationFulfilled = NO;
    __block BOOL hasWiFi = NO;
    __block BOOL hasCellular = NO;
    NSInteger expectedCallbackCount = 2;  // 期望2次回调（Wi-Fi + 蜂窝）
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://www.baidu.com";
    request.appKey = kTestAppKey;
    request.timeout = 15000;  // 15秒，单位ms
    request.enableMultiplePortsDetect = YES;  // 启用多网卡探测
    request.detectEx = @{@"case_id": @"HTTP-010", @"test_scene": @"multi_port_network"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        @try {
            callbackCount++;
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:[NSString stringWithFormat:@"HTTP多网卡探测结果 #%ld", (long)callbackCount]];
            
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
            
            // 验证HTTP特有字段
            XCTAssertNotNil(origin[@"httpCode"], @"httpCode不应为空");
            XCTAssertNotNil(origin[@"requestTime"], @"requestTime不应为空");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        }
        
        // 收到预期回调数后立即完成测试
        if (callbackCount >= expectedCallbackCount && !expectationFulfilled) {
            expectationFulfilled = YES;
            
            NSLog(@"📊 HTTP多网卡探测结果汇总:");
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

/// 【HTTP-011】验证当前网络环境识别（单网卡模式）
- (void)testHttpCurrentNetworkIdentification {
    NSLog(@"🧪 开始执行用例HTTP-011：当前网络环境识别（单网卡）");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP-网络识别"];
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://www.tencentcloud.com";
    request.appKey = kTestAppKey;
    request.timeout = 15000;  // 15秒，单位ms
    request.enableMultiplePortsDetect = NO;  // 单网卡探测
    request.detectEx = @{@"case_id": @"HTTP-011", @"test_scene": @"network_identification"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"HTTP当前网络环境识别结果"];
            
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
            NSLog(@"   - interface: %@", origin[@"interface"]);
            
            // 验证usedNet和defaultNet的一致性（单网卡模式下应该一致）
            NSString *usedNet = netInfo[@"usedNet"];
            NSString *defaultNet = netInfo[@"defaultNet"];
            XCTAssertNotNil(usedNet, @"usedNet不应为空");
            XCTAssertNotNil(defaultNet, @"defaultNet不应为空");
            
            // 单网卡模式下，usedNet应该和defaultNet表示同一种网络类型
            NSString *normalizedUsedNet = [[usedNet lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
            NSString *normalizedDefaultNet = [[defaultNet lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
            XCTAssertTrue([normalizedUsedNet isEqualToString:normalizedDefaultNet], 
                         @"单网卡模式下usedNet应等于defaultNet，usedNet=%@, defaultNet=%@", usedNet, defaultNet);
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【HTTP-012】验证多网卡探测产生多个网络类型结果
/// 注意：需要设备同时连接Wi-Fi和蜂窝数据才能检测到多种网络类型
/// 验证点：必须同时检测到Wi-Fi和蜂窝网络(4G/5G等)
- (void)testHttpMultipleNetworkTypesDetection {
    NSLog(@"🧪 开始执行用例HTTP-012：多网络类型探测");
    NSLog(@"⚠️ 注意：此测试需要设备同时开启Wi-Fi和蜂窝数据");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP-多网络类型"];
    
    __block NSMutableSet<NSString *> *networkTypes = [NSMutableSet set];
    __block NSMutableSet<NSString *> *interfaces = [NSMutableSet set];
    __block NSInteger callbackCount = 0;
    __block BOOL expectationFulfilled = NO;
    __block BOOL hasWiFi = NO;
    __block BOOL hasCellular = NO;
    NSInteger expectedCallbackCount = 2;  // 预期2次回调（Wi-Fi + 蜂窝）
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://www.tencentcloud.com";
    request.enableSSLVerification = true;
    request.appKey = kTestAppKey;
    request.timeout = 15000;  // 15秒，单位ms
    request.enableMultiplePortsDetect = YES;
    request.detectEx = @{@"case_id": @"HTTP-012", @"test_scene": @"multi_network_types"};
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
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
            
        } @catch (NSException *exception) {
            NSLog(@"⚠️ 回调#%ld 处理异常: %@", (long)callbackCount, exception.reason);
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:^(NSError *error) {
        if (error) {
            NSLog(@"❌ 测试超时 - Wi-Fi: %@, 蜂窝: %@", hasWiFi ? @"✅" : @"❌", hasCellular ? @"✅" : @"❌");
        }
    }];
}

/// 【HTTP-013】对比测试 enableMultiplePortsDetect=false 和 true 的行为差异
/// 验证点：false=1次回调(单网卡), true=2次回调且包含Wi-Fi和蜂窝网络
- (void)testHttpMultiplePortsCompare {
    NSLog(@"🧪 开始执行用例HTTP-013：多网卡参数对比测试");
    NSLog(@"⚠️ 注意：此测试需要设备同时开启Wi-Fi和蜂窝数据以观察差异");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP-多网卡对比"];
    
    __block NSInteger falseCallbackCount = 0;
    __block NSInteger trueCallbackCount = 0;
    __block NSMutableSet<NSString *> *falseNetworkTypes = [NSMutableSet set];
    __block NSMutableSet<NSString *> *trueNetworkTypes = [NSMutableSet set];
    __block BOOL trueHasWiFi = NO;
    __block BOOL trueHasCellular = NO;
    __block BOOL trueExpectationFulfilled = NO;
    NSInteger expectedTrueCallbackCount = 2;
    
    // 第一阶段：enableMultiplePortsDetect = NO
    CLSHttpRequest *request1 = [[CLSHttpRequest alloc] init];
    request1.domain = @"https://www.baidu.com";
    request1.appKey = kTestAppKey;
    request1.timeout = 10000;  // 10秒，单位ms
    request1.enableMultiplePortsDetect = NO;
    request1.detectEx = @{@"case_id": @"HTTP-013-false"};
    
    [self.diagnosis httpingv2:request1 complate:^(CLSResponse *response) {
        falseCallbackCount++;
        NSDictionary *data = [self parseResponseContent:response];
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        NSDictionary *netInfo = [self safeConvertToDictionary:origin[@"netInfo"]];
        NSString *usedNet = netInfo[@"usedNet"];
        if (usedNet) [falseNetworkTypes addObject:usedNet];
        NSLog(@"📍 enableMultiplePortsDetect=false 回调#%ld, usedNet: %@", (long)falseCallbackCount, usedNet);
    }];
    
    // 等待第一阶段完成后进行第二阶段
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"📍 第一阶段完成，开始第二阶段测试");
        
        // 第二阶段：enableMultiplePortsDetect = YES
        CLSHttpRequest *request2 = [[CLSHttpRequest alloc] init];
        request2.domain = @"https://www.baidu.com";
        request2.appKey = kTestAppKey;
        request2.timeout = 10000;  // 10秒，单位ms
        request2.enableMultiplePortsDetect = YES;
        request2.detectEx = @{@"case_id": @"HTTP-013-true"};
        
        [self.diagnosis httpingv2:request2 complate:^(CLSResponse *response) {
            trueCallbackCount++;
            NSDictionary *data = [self parseResponseContent:response];
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            NSDictionary *netInfo = [self safeConvertToDictionary:origin[@"netInfo"]];
            NSString *usedNet = netInfo[@"usedNet"];
            
            if (usedNet) {
                [trueNetworkTypes addObject:usedNet];
                
                // 判断网络类型
                NSString *lowerUsedNet = [usedNet lowercaseString];
                if ([lowerUsedNet containsString:@"wifi"] || [lowerUsedNet containsString:@"wi-fi"]) {
                    trueHasWiFi = YES;
                } else if ([lowerUsedNet containsString:@"4g"] || 
                           [lowerUsedNet containsString:@"5g"] || 
                           [lowerUsedNet containsString:@"3g"] || 
                           [lowerUsedNet containsString:@"2g"] || 
                           [lowerUsedNet containsString:@"cellular"] ||
                           [lowerUsedNet containsString:@"lte"] ||
                           [lowerUsedNet containsString:@"wwan"]) {
                    trueHasCellular = YES;
                }
            }
            NSLog(@"📍 enableMultiplePortsDetect=true 回调#%ld, usedNet: %@", (long)trueCallbackCount, usedNet);
            
            // 收到预期回调数后完成测试
            if (trueCallbackCount >= expectedTrueCallbackCount && !trueExpectationFulfilled) {
                trueExpectationFulfilled = YES;
                
                NSLog(@"📊 对比测试结果:");
                NSLog(@"   - enableMultiplePortsDetect=false: 回调%ld次, 网络类型: %@", (long)falseCallbackCount, falseNetworkTypes);
                NSLog(@"   - enableMultiplePortsDetect=true:  回调%ld次, 网络类型: %@", (long)trueCallbackCount, trueNetworkTypes);
                NSLog(@"   - true模式 Wi-Fi: %@, 蜂窝: %@", trueHasWiFi ? @"✅" : @"❌", trueHasCellular ? @"✅" : @"❌");
                
                // 核心断言
                XCTAssertEqual(falseCallbackCount, 1, @"enableMultiplePortsDetect=false时应只有1次回调");
                XCTAssertEqual(trueCallbackCount, expectedTrueCallbackCount, 
                              @"enableMultiplePortsDetect=true时应有%ld次回调，实际: %ld", 
                              (long)expectedTrueCallbackCount, (long)trueCallbackCount);
                XCTAssertTrue(trueHasWiFi, @"true模式应检测到Wi-Fi网络，实际: %@", trueNetworkTypes);
                XCTAssertTrue(trueHasCellular, @"true模式应检测到蜂窝网络，实际: %@", trueNetworkTypes);
                
                [expectation fulfill];
            }
        }];
    });
    
    [self waitForExpectationsWithTimeout:60 handler:^(NSError *error) {
        if (error) {
            NSLog(@"❌ 测试超时");
            NSLog(@"   - false模式回调: %ld次", (long)falseCallbackCount);
            NSLog(@"   - true模式回调: %ld次 (期望: %ld)", (long)trueCallbackCount, (long)expectedTrueCallbackCount);
            NSLog(@"   - Wi-Fi: %@, 蜂窝: %@", trueHasWiFi ? @"✅" : @"❌", trueHasCellular ? @"✅" : @"❌");
        }
    }];
}

@end
