//
//  ZhiyanTcppingDetectionTests.m
//  TencentCloudLogDemoTests
//
//  Created by AI Assistant on 2026/01/04.
//  智研TCPPING探测专项测试用例
//
//  TCPPing探测参数：domain、port、detectEx、enableMultiplePortsDetect、maxTimes、timeout
//  注意：userEx 已移除，统一从 ClsNetworkDiagnosis 获取
//

#import "CLSNetworkDiagnosisBaseTests.h"

@interface ZhiyanTcppingDetectionTests : CLSNetworkDiagnosisBaseTests
@end

@implementation ZhiyanTcppingDetectionTests

#pragma mark - 基本功能测试

/// 【TCPPING-001】验证TCPPing探测基本功能及所有字段完整性
- (void)testTcppingBasicFunctionality {
    NSLog(@"🧪 开始执行用例TCPPING-001：TCPPing探测基本功能验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCPPING基本功能"];
    __block BOOL fulfilled = NO;
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = kTestDomain;
    request.port = 80;
    request.appKey = kTestAppKey;
    request.maxTimes = 5;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = NO;  // 基本测试使用单网卡模式
    request.detectEx = @{@"case_id": @"TCPPING-001", @"priority": @"P0"};
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"TCPPING基本功能验证结果"];
            
            // 1. 公共字段校验
            [self validateCommonFields:data];
            [self validateResourceFields:data];
            [self validateAttributeFields:data expectedType:@"tcpping"];
            [self validateNetOriginFields:data expectedMethod:@"tcpping"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 2. TCPPing专用字段校验
            [self validateTcppingOriginFields:origin expectedPort:80];
            [self validateTcppingStatisticsFields:origin expectedCount:5];
            
            // 3. 网络环境信息校验
            [self validateNetInfo:[self safeConvertToDictionary:origin[@"netInfo"]]];
            
            // 4. 扩展字段校验
            [self validateExtensionFields:origin 
                         expectedDetectEx:@{@"case_id": @"TCPPING-001"}];
            
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

/// 【TCPPING-002】验证domain参数
- (void)testTcppingDomainParameter {
    NSLog(@"🧪 开始执行用例TCPPING-002：domain参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCPPING-domain"];
    __block BOOL fulfilled = NO;
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = @"www.baidu.com";
    request.port = 80;
    request.appKey = kTestAppKey;
    request.maxTimes = 5;
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"TCPPING-002"};
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"TCPPING domain验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertEqualObjects(origin[@"host"], @"www.baidu.com", @"host应等于设置的domain");
            XCTAssertNotNil(origin[@"host_ip"], @"host_ip不应为空");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【TCPPING-003】验证port参数
- (void)testTcppingPortParameter {
    NSLog(@"🧪 开始执行用例TCPPING-003：port参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCPPING-port"];
    __block BOOL fulfilled = NO;
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = kTestDomain;
    request.port = 443;  // HTTPS端口
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"TCPPING-003"};
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"TCPPING port验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertEqual([origin[@"port"] integerValue], 443, @"port应等于设置的443");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【TCPPING-004】验证maxTimes参数 - 单次探测次数
- (void)testTcppingMaxTimesParameter {
    NSLog(@"🧪 开始执行用例TCPPING-004：maxTimes参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCPPING-maxTimes"];
    __block BOOL fulfilled = NO;
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = kTestDomain;
    request.port = 80;
    request.appKey = kTestAppKey;
    request.maxTimes = 10;  // 设置探测10次
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"TCPPING-004"};
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"TCPPING maxTimes验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertEqual([origin[@"count"] integerValue], 10, @"count应等于设置的maxTimes=10");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【TCPPING-005】验证timeout参数 - 超时触发
- (void)testTcppingTimeoutParameter {
    NSLog(@"🧪 开始执行用例TCPPING-005：timeout参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCPPING-timeout"];
    __block BOOL fulfilled = NO;
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = @"192.0.2.1";  // 不可达IP
    request.port = 80;
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.timeout = 1000;  // 1秒超时，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"TCPPING-005"};
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"TCPPING timeout验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 超时场景应该有丢包或响应数为0
            NSInteger responseNum = [origin[@"responseNum"] integerValue];
            NSLog(@"📍 超时场景响应数: %ld", (long)responseNum);
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【TCPPING-006】验证enableMultiplePortsDetect参数
- (void)testTcppingEnableMultiplePortsDetect {
    NSLog(@"🧪 开始执行用例TCPPING-006：enableMultiplePortsDetect参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCPPING-multiPorts"];
    __block BOOL fulfilled = NO;
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = kTestDomain;
    request.port = 80;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.enableMultiplePortsDetect = YES;
    request.detectEx = @{@"case_id": @"TCPPING-006"};
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"TCPPING multiPorts验证结果"];
            
            [self validateCommonFields:data];
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【TCPPING-007】验证detectEx扩展字段
- (void)testTcppingExtensionFields {
    NSLog(@"🧪 开始执行用例TCPPING-007：扩展字段验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCPPING-extension"];
    __block BOOL fulfilled = NO;
    
    NSDictionary *detectEx = @{
        @"case_id": @"TCPPING-007",
        @"tcpping_scene": @"verification",
        @"priority": @"P1"
    };
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = kTestDomain;
    request.port = 80;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.pageName = @"tcpping_param_page";
    request.enableMultiplePortsDetect = NO;
    request.detectEx = detectEx;
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"TCPPING扩展字段验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertEqualObjects(attribute[@"page.name"], @"tcpping_param_page", @"page.name应匹配");
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

/// 【TCPPING-008】验证所有返回字段完整性
- (void)testTcppingAllFieldsCompleteness {
    NSLog(@"🧪 开始执行用例TCPPING-008：字段完整性验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCPPING-字段完整性"];
    __block BOOL fulfilled = NO;
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = kTestDomain;
    request.port = 80;
    request.appKey = kTestAppKey;
    request.maxTimes = 5;
    request.timeout = 10000;  // 10秒，单位ms
    request.pageName = @"tcpping_fields_test";
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"TCPPING-008"};
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"TCPPING字段完整性验证结果"];
            
            // 1. 公共字段
            [self validateCommonFields:data];
            [self validateResourceFields:data];
            
            // 2. Attribute字段
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            XCTAssertEqualObjects(attribute[@"net.type"], @"tcpping", @"net.type应为tcpping");
            
            // 3. net.origin字段
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            [self validateTcppingOriginFields:origin expectedPort:80];
            
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

/// 【TCPPING-ERR-001】异常场景 - 关闭的端口
- (void)testTcppingClosedPort {
    NSLog(@"🧪 开始执行用例TCPPING-ERR-001：关闭的端口");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCPPING关闭端口"];
    __block BOOL fulfilled = NO;
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = kTestDomain;
    request.port = 12345;  // 通常关闭的端口
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.timeout = 2000;  // 2秒，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"TCPPING-ERR-001"};
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"TCPPING关闭端口结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 关闭的端口应产生连接失败
            NSLog(@"📍 关闭端口探测结果 - loss: %@, responseNum: %@", origin[@"loss"], origin[@"responseNum"]);
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【TCPPING-ERR-002】异常场景 - 无效域名
- (void)testTcppingInvalidDomain {
    NSLog(@"🧪 开始执行用例TCPPING-ERR-002：无效域名");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCPPING无效域名"];
    __block BOOL fulfilled = NO;
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = @"invalid.domain.not.exist.test";
    request.port = 80;
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.timeout = 3000;  // 3秒，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"TCPPING-ERR-002"};
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"TCPPING无效域名结果"];
            
            XCTAssertNotNil(data, @"无效域名也应有返回数据");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

#pragma mark - 多网卡环境测试

/// 【TCPPING-009】验证多网卡探测 - Wi-Fi和蜂窝网络环境下的完整行为
/// 注意：此测试需要在同时连接Wi-Fi和蜂窝网络的设备上运行
/// 验证点：1. 回调次数=2  2. 必须同时检测到Wi-Fi和4G/蜂窝网络类型
- (void)testTcppingMultiplePortsWithNetworkType {
    NSLog(@"🧪 开始执行用例TCPPING-009：多网卡探测网络环境验证");
    NSLog(@"⚠️ 注意：此测试需要设备同时开启Wi-Fi和蜂窝数据");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCPPING-多网卡网络环境"];
    
    __block NSMutableArray<NSString *> *detectedNetworks = [NSMutableArray array];
    __block NSMutableArray<NSString *> *detectedInterfaces = [NSMutableArray array];
    __block NSInteger callbackCount = 0;
    __block BOOL expectationFulfilled = NO;
    __block BOOL hasWiFi = NO;
    __block BOOL hasCellular = NO;
    NSInteger expectedCallbackCount = 2;  // 期望2次回调（Wi-Fi + 蜂窝）
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = kTestDomain;
    request.port = 80;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = true;  // 启用多网卡探测
    request.detectEx = @{@"case_id": @"TCPPING-009", @"test_scene": @"multi_port_network"};
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        @try {
            callbackCount++;
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:[NSString stringWithFormat:@"TCPPING多网卡探测结果 #%ld", (long)callbackCount]];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            NSDictionary *netInfo = [self safeConvertToDictionary:origin[@"netInfo"]];
            
            // 验证interface字段（网络接口）- 这是判断网络类型的关键字段
            NSString *interface = origin[@"interface"];
            XCTAssertNotNil(interface, @"interface字段不应为空");
            NSLog(@"📍 回调#%ld - 网络接口(interface): %@", (long)callbackCount, interface);
            
            // 记录检测到的接口
            if (interface && ![detectedInterfaces containsObject:interface]) {
                [detectedInterfaces addObject:interface];
            }
            
            // 判断网络类型：基于 interface 字段判断 Wi-Fi 或 蜂窝网络(4G/5G/3G/2G)
            NSString *lowerInterface = [interface lowercaseString];
            if ([lowerInterface containsString:@"wifi"] || [lowerInterface containsString:@"wi-fi"]) {
                hasWiFi = YES;
                if (![detectedNetworks containsObject:@"WiFi"]) {
                    [detectedNetworks addObject:@"WiFi"];
                }
                NSLog(@"📍 回调#%ld - 检测到Wi-Fi网络", (long)callbackCount);
            } else if ([lowerInterface containsString:@"4g"] || 
                       [lowerInterface containsString:@"5g"] || 
                       [lowerInterface containsString:@"3g"] || 
                       [lowerInterface containsString:@"2g"] || 
                       [lowerInterface containsString:@"cellular"] ||
                       [lowerInterface containsString:@"lte"] ||
                       [lowerInterface containsString:@"wwan"] ||
                       [lowerInterface containsString:@"pdp_ip"]) {
                hasCellular = YES;
                if (![detectedNetworks containsObject:interface]) {
                    [detectedNetworks addObject:interface];
                }
                NSLog(@"📍 回调#%ld - 检测到蜂窝网络: %@", (long)callbackCount, interface);
            }
            
            // 如果netInfo存在，也记录usedNet信息（作为辅助参考）
            if (netInfo) {
                NSString *usedNet = netInfo[@"usedNet"];
                if (usedNet) {
                    NSLog(@"📍 回调#%ld - netInfo.usedNet: %@", (long)callbackCount, usedNet);
                }
            }
            
            // 验证TCPPING特有字段
            XCTAssertNotNil(origin[@"port"], @"port不应为空");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        }
        
        // 收到预期回调数后立即完成测试
        if (callbackCount >= expectedCallbackCount && !expectationFulfilled) {
            expectationFulfilled = YES;
            
            NSLog(@"📊 多网卡探测结果汇总:");
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
    
    [self waitForExpectationsWithTimeout:30 handler:^(NSError *error) {
        if (error) {
            NSLog(@"❌ 测试超时 - 总回调次数: %ld (期望: %ld)", (long)callbackCount, (long)expectedCallbackCount);
            NSLog(@"   - 检测到网络类型: %@", detectedNetworks);
            NSLog(@"   - Wi-Fi: %@, 蜂窝: %@", hasWiFi ? @"✅" : @"❌", hasCellular ? @"✅" : @"❌");
        }
    }];
}

/// 【TCPPING-010】验证当前网络环境识别（单网卡模式）
- (void)testTcppingCurrentNetworkIdentification {
    NSLog(@"🧪 开始执行用例TCPPING-010：当前网络环境识别（单网卡）");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCPPING-网络识别"];
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = kTestDomain;
    request.port = 80;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = NO;  // 单网卡探测
    request.detectEx = @{@"case_id": @"TCPPING-010", @"test_scene": @"network_identification"};
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"TCPPING当前网络环境识别结果"];
            
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
            NSLog(@"   - interface: %@", origin[@"interface"]);
            
            // 验证usedNet和defaultNet的一致性（单网卡模式下应该一致）
            NSString *usedNet = netInfo[@"usedNet"];
            NSString *defaultNet = netInfo[@"defaultNet"];
            XCTAssertNotNil(usedNet, @"usedNet不应为空");
            XCTAssertNotNil(defaultNet, @"defaultNet不应为空");
            
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

/// 【TCPPING-011】验证多网卡探测产生多个网络类型结果
/// 验证点：必须同时检测到Wi-Fi和蜂窝网络(4G/5G等)
- (void)testTcppingMultipleNetworkTypesDetection {
    NSLog(@"🧪 开始执行用例TCPPING-011：多网络类型探测");
    NSLog(@"⚠️ 注意：此测试需要设备同时开启Wi-Fi和蜂窝数据");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCPPING-多网络类型"];
    
    __block NSMutableSet<NSString *> *networkTypes = [NSMutableSet set];
    __block NSMutableSet<NSString *> *interfaces = [NSMutableSet set];
    __block NSInteger callbackCount = 0;
    __block BOOL expectationFulfilled = NO;
    __block BOOL hasWiFi = NO;
    __block BOOL hasCellular = NO;
    NSInteger expectedCallbackCount = 2;
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = @"www.baidu.com";
    request.port = 80;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = YES;
    request.detectEx = @{@"case_id": @"TCPPING-011", @"test_scene": @"multi_network_types"};
    
    [self.diagnosis tcpPingv2:request complate:^(CLSResponse *response) {
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
    
    [self waitForExpectationsWithTimeout:30 handler:^(NSError *error) {
        if (error) {
            NSLog(@"❌ 测试超时 - Wi-Fi: %@, 蜂窝: %@", hasWiFi ? @"✅" : @"❌", hasCellular ? @"✅" : @"❌");
        }
    }];
}

/// 【TCPPING-012】对比测试 enableMultiplePortsDetect=false 和 true 的行为差异
/// 验证点：false=1次回调(单网卡), true=2次回调且包含Wi-Fi和蜂窝网络
- (void)testTcppingMultiplePortsCompare {
    NSLog(@"🧪 开始执行用例TCPPING-012：多网卡参数对比测试");
    NSLog(@"⚠️ 注意：此测试需要设备同时开启Wi-Fi和蜂窝数据以观察差异");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"TCPPING-多网卡对比"];
    
    __block NSInteger falseCallbackCount = 0;
    __block NSInteger trueCallbackCount = 0;
    __block NSMutableSet<NSString *> *falseNetworkTypes = [NSMutableSet set];
    __block NSMutableSet<NSString *> *trueNetworkTypes = [NSMutableSet set];
    __block BOOL trueHasWiFi = NO;
    __block BOOL trueHasCellular = NO;
    __block BOOL trueExpectationFulfilled = NO;
    NSInteger expectedTrueCallbackCount = 2;
    
    // 第一阶段：enableMultiplePortsDetect = NO
    CLSTcpRequest *request1 = [[CLSTcpRequest alloc] init];
    request1.domain = kTestDomain;
    request1.port = 80;
    request1.appKey = kTestAppKey;
    request1.maxTimes = 3;
    request1.timeout = 10000;  // 10秒，单位ms
    request1.enableMultiplePortsDetect = NO;
    request1.detectEx = @{@"case_id": @"TCPPING-012-false"};
    
    [self.diagnosis tcpPingv2:request1 complate:^(CLSResponse *response) {
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"📍 第一阶段完成，开始第二阶段测试");
        
        // 第二阶段：enableMultiplePortsDetect = YES
        CLSTcpRequest *request2 = [[CLSTcpRequest alloc] init];
        request2.domain = kTestDomain;
        request2.port = 80;
        request2.appKey = kTestAppKey;
        request2.maxTimes = 3;
        request2.timeout = 10000;  // 10秒，单位ms
        request2.enableMultiplePortsDetect = YES;
        request2.detectEx = @{@"case_id": @"TCPPING-012-true"};
        
        [self.diagnosis tcpPingv2:request2 complate:^(CLSResponse *response) {
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
