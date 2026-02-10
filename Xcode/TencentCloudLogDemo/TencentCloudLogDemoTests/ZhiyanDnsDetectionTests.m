//
//  ZhiyanDnsDetectionTests.m
//  TencentCloudLogDemoTests
//
//  Created by AI Assistant on 2026/01/04.
//  智研DNS探测专项测试用例
//
//  DNS探测参数：domain、detectEx、enableMultiplePortsDetect、prefer、nameserver、timeout
//  注意：userEx 已移除，统一从 ClsNetworkDiagnosis 获取
//

#import "CLSNetworkDiagnosisBaseTests.h"

@interface ZhiyanDnsDetectionTests : CLSNetworkDiagnosisBaseTests
@end

@implementation ZhiyanDnsDetectionTests

#pragma mark - 基本功能测试

/// 【DNS-001】验证DNS探测基本功能及所有字段完整性
- (void)testDnsBasicFunctionality {
    NSLog(@"🧪 开始执行用例DNS-001：DNS探测基本功能验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS基本功能"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"114.114.114.114";
    request.appKey = kTestAppKey;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = NO;  // 基本测试使用单网卡模式
    request.detectEx = @{@"case_id": @"DNS-001", @"priority": @"P0"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS基本功能验证结果"];
            
            // 1. 公共字段校验
            [self validateCommonFields:data];
            [self validateResourceFields:data];
            [self validateAttributeFields:data expectedType:@"dns"];
            [self validateNetOriginFields:data expectedMethod:@"dns"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 2. DNS专用字段校验
            [self validateDnsOriginFields:origin];
            XCTAssertEqualObjects(origin[@"status"], @"NOERROR", @"正常解析应返回NOERROR");
            
            // 3. DNS解析结果校验
            [self validateDnsAnswerFields:origin];
            
            // 4. 网络环境信息校验
            [self validateNetInfo:[self safeConvertToDictionary:origin[@"netInfo"]]];
            
            // 5. 扩展字段校验
            [self validateExtensionFields:origin 
                         expectedDetectEx:@{@"case_id": @"DNS-001"}];
            
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

/// 【DNS-002】验证domain参数
- (void)testDnsDomainParameter {
    NSLog(@"🧪 开始执行用例DNS-002：domain参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-domain"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = @"www.tencent.com";
    request.appKey = kTestAppKey;
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-002"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS domain验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertEqualObjects(origin[@"domain"], @"www.tencent.com", @"domain应匹配设置值");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【DNS-003】验证nameserver参数 - 单服务器
- (void)testDnsNameServerSingle {
    NSLog(@"🧪 开始执行用例DNS-003：nameserver参数验证（单服务器）");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-nameserver单"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"119.29.29.29";  // 腾讯DNSPod
    request.appKey = kTestAppKey;
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-003"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS nameserver验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertEqualObjects(origin[@"host_ip"], @"119.29.29.29", @"host_ip应为设置的nameserver");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【DNS-004】验证nameserver参数 - 多服务器
- (void)testDnsNameServerMultiple {
    NSLog(@"🧪 开始执行用例DNS-004：nameserver参数验证（多服务器）");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-nameserver多"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"8.8.8.8,114.114.114.114";  // 多服务器用逗号分隔
    request.appKey = kTestAppKey;
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-004"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS nameserver多服务器验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 应使用其中一个服务器
            NSString *usedServer = origin[@"host_ip"];
            XCTAssertNotNil(usedServer, @"host_ip不应为空");
            NSLog(@"📍 使用的DNS服务器: %@", usedServer);
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【DNS-005】验证timeout参数 - 超时触发
- (void)testDnsTimeoutParameter {
    NSLog(@"🧪 开始执行用例DNS-005：timeout参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-timeout"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"192.0.2.1";  // 不可达服务器
    request.timeout = 1000;  // 1秒超时，单位ms
    request.appKey = kTestAppKey;
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-005"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS timeout验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 超时应有错误码或特定状态
            NSLog(@"📍 超时场景 - status: %@, errCode: %@", origin[@"status"], origin[@"errCode"]);
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【DNS-006】验证prefer参数 - IPv4优先
- (void)testDnsPreferIPv4First {
    NSLog(@"🧪 开始执行用例DNS-006：prefer参数验证 - IPv4优先");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-prefer-IPv4"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"114.114.114.114";
    request.appKey = kTestAppKey;
    request.prefer = 0;  // IPv4优先
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-006", @"prefer_mode": @"IPv4优先"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS IPv4优先验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertNotNil(origin[@"status"], @"status不应为空");
            NSLog(@"📍 IPv4优先模式 - status: %@", origin[@"status"]);
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【DNS-007】验证prefer参数 - IPv6优先
- (void)testDnsPreferIPv6First {
    NSLog(@"🧪 开始执行用例DNS-007：prefer参数验证 - IPv6优先");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-prefer-IPv6"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"114.114.114.114";
    request.appKey = kTestAppKey;
    request.prefer = 1;  // IPv6优先
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-007", @"prefer_mode": @"IPv6优先"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS IPv6优先验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertNotNil(origin[@"status"], @"status不应为空");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【DNS-008】验证prefer参数 - IPv4 Only
- (void)testDnsPreferIPv4Only {
    NSLog(@"🧪 开始执行用例DNS-008：prefer参数验证 - IPv4 Only");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-prefer-IPv4Only"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"114.114.114.114";
    request.appKey = kTestAppKey;
    request.prefer = 2;  // IPv4 Only
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-008", @"prefer_mode": @"IPv4Only"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS IPv4 Only验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // IPv4 Only 应该只查询 A 记录
            XCTAssertEqualObjects(origin[@"status"], @"NOERROR", @"状态应为NOERROR");
            
            // 验证返回的 host_ip 必须是 IPv4 地址
            NSString *hostIP = origin[@"host_ip"];
            XCTAssertNotNil(hostIP, @"host_ip不应为空");
            XCTAssertTrue([self isIPv4Address:hostIP], @"IPv4 Only模式应返回IPv4地址，实际: %@", hostIP);
            NSLog(@"✅ IPv4 Only DNS验证通过: %@", hostIP);
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【DNS-009】验证prefer参数 - IPv6 Only
- (void)testDnsPreferIPv6Only {
    NSLog(@"🧪 开始执行用例DNS-009：prefer参数验证 - IPv6 Only");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-prefer-IPv6Only"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = @"www.baidu.com";
    request.nameServer = @"114.114.114.114";
    request.appKey = kTestAppKey;
    request.prefer = 3;  // IPv6 Only
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-009", @"prefer_mode": @"IPv6Only"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS IPv6 Only验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // IPv6 Only 应该只查询 AAAA 记录
            NSString *hostIP = origin[@"host_ip"];
            XCTAssertNotNil(hostIP, @"host_ip不应为空");
            NSLog(@"📍 IPv6 Only DNS结果 - host_ip: %@", hostIP);
            
            XCTAssertTrue([self isIPv6Address:hostIP], @"IPv6 Only模式应返回IPv6地址，实际: %@", hostIP);
            NSLog(@"✅ IPv6 Only DNS验证通过: %@", hostIP);
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【DNS-010】验证enableMultiplePortsDetect参数
- (void)testDnsEnableMultiplePortsDetect {
    NSLog(@"🧪 开始执行用例DNS-010：enableMultiplePortsDetect参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-multiPorts"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"114.114.114.114";
    request.appKey = kTestAppKey;
    request.enableMultiplePortsDetect = YES;
    request.detectEx = @{@"case_id": @"DNS-010"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS multiPorts验证结果"];
            
            [self validateCommonFields:data];
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【DNS-011】验证detectEx扩展字段
- (void)testDnsExtensionFields {
    NSLog(@"🧪 开始执行用例DNS-011：扩展字段验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-extension"];
    __block BOOL fulfilled = NO;
    
    NSDictionary *detectEx = @{
        @"case_id": @"DNS-011",
        @"dns_scene": @"comprehensive_test",
        @"priority": @"P1"
    };
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"119.29.29.29";
    request.appKey = kTestAppKey;
    request.pageName = @"dns_param_page";
    request.enableMultiplePortsDetect = NO;
    request.detectEx = detectEx;
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS扩展字段验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertEqualObjects(attribute[@"page.name"], @"dns_param_page", @"page.name应匹配");
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

/// 【DNS-012】验证所有返回字段完整性
- (void)testDnsAllFieldsCompleteness {
    NSLog(@"🧪 开始执行用例DNS-012：字段完整性验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-字段完整性"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"114.114.114.114";
    request.appKey = kTestAppKey;
    request.timeout = 10000;  // 10秒，单位ms
    request.pageName = @"dns_fields_test";
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-012"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS字段完整性验证结果"];
            
            // 1. 公共字段
            [self validateCommonFields:data];
            [self validateResourceFields:data];
            
            // 2. Attribute字段
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            XCTAssertEqualObjects(attribute[@"net.type"], @"dns", @"net.type应为dns");
            
            // 3. net.origin字段
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            [self validateDnsOriginFields:origin];
            
            // 4. 验证src字段
            XCTAssertEqualObjects(origin[@"src"], @"app", @"src应为app");
            
            // 5. netInfo字段
            [self validateNetInfo:[self safeConvertToDictionary:origin[@"netInfo"]]];
            
            // 6. 验证DNS特有字段
            XCTAssertNotNil(origin[@"QUESTION_SECTION"], @"应包含QUESTION_SECTION");
            XCTAssertNotNil(origin[@"QUERY"], @"应包含QUERY");
            XCTAssertNotNil(origin[@"ANSWER"], @"应包含ANSWER");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

#pragma mark - 异常场景测试

/// 【DNS-ERR-001】异常场景 - 不存在的域名
- (void)testDnsNonExistentDomain {
    NSLog(@"🧪 开始执行用例DNS-ERR-001：不存在的域名");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS不存在域名"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = @"a.very.unlikely.domain.that.does.not.exist.com";
    request.appKey = kTestAppKey;
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-ERR-001"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS不存在域名结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 不存在的域名应返回 NXDOMAIN
            XCTAssertEqualObjects(origin[@"status"], @"NXDOMAIN", @"不存在域名应返回NXDOMAIN");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【DNS-ERR-002】异常场景 - 无效DNS服务器
- (void)testDnsInvalidNameServer {
    NSLog(@"🧪 开始执行用例DNS-ERR-002：无效DNS服务器");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS无效服务器"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"192.0.2.1";  // 不可达IP
    request.timeout = 2000;  // 2秒，单位ms
    request.appKey = kTestAppKey;
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-ERR-002"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS无效服务器结果"];
            
            // 无效服务器也应有返回数据
            XCTAssertNotNil(data, @"无效服务器也应有返回数据");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

#pragma mark - 多网卡环境测试

/// 【DNS-013】验证多网卡探测 - Wi-Fi和蜂窝网络环境下的完整行为
/// 注意：此测试需要在同时连接Wi-Fi和蜂窝网络的设备上运行
/// 验证点：1. 回调次数=2  2. 必须同时检测到Wi-Fi和4G/蜂窝网络类型
- (void)testDnsMultiplePortsWithNetworkType {
    NSLog(@"🧪 开始执行用例DNS-013：多网卡探测网络环境验证");
    NSLog(@"⚠️ 注意：此测试需要设备同时开启Wi-Fi和蜂窝数据");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-多网卡网络环境"];
    
    __block NSMutableArray<NSString *> *detectedNetworks = [NSMutableArray array];
    __block NSMutableArray<NSString *> *detectedInterfaces = [NSMutableArray array];
    __block NSInteger callbackCount = 0;
    __block BOOL expectationFulfilled = NO;
    __block BOOL hasWiFi = NO;
    __block BOOL hasCellular = NO;
    NSInteger expectedCallbackCount = 2;  // 期望2次回调（Wi-Fi + 蜂窝）
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"114.114.114.114";
    request.appKey = kTestAppKey;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = YES;  // 启用多网卡探测
    request.detectEx = @{@"case_id": @"DNS-013", @"test_scene": @"multi_port_network"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        @try {
            callbackCount++;
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:[NSString stringWithFormat:@"DNS多网卡探测结果 #%ld", (long)callbackCount]];
            
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
            
            // 验证DNS特有字段
            XCTAssertNotNil(origin[@"status"], @"status不应为空");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        }
        
        // 收到预期回调数后立即完成测试
        if (callbackCount >= expectedCallbackCount && !expectationFulfilled) {
            expectationFulfilled = YES;
            
            NSLog(@"📊 DNS多网卡探测结果汇总:");
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

/// 【DNS-014】验证当前网络环境识别（单网卡模式）
- (void)testDnsCurrentNetworkIdentification {
    NSLog(@"🧪 开始执行用例DNS-014：当前网络环境识别（单网卡）");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-网络识别"];
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"119.29.29.29";
    request.appKey = kTestAppKey;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = false;  // 单网卡探测
    request.detectEx = @{@"case_id": @"DNS-014", @"test_scene": @"network_identification"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS当前网络环境识别结果"];
            
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

/// 【DNS-015】验证多网卡探测产生多个网络类型结果
/// 验证点：必须同时检测到Wi-Fi和蜂窝网络(4G/5G等)
- (void)testDnsMultipleNetworkTypesDetection {
    NSLog(@"🧪 开始执行用例DNS-015：多网络类型探测");
    NSLog(@"⚠️ 注意：此测试需要设备同时开启Wi-Fi和蜂窝数据");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-多网络类型"];
    
    __block NSMutableSet<NSString *> *networkTypes = [NSMutableSet set];
    __block NSMutableSet<NSString *> *interfaces = [NSMutableSet set];
    __block NSInteger callbackCount = 0;
    __block BOOL expectationFulfilled = NO;
    __block BOOL hasWiFi = NO;
    __block BOOL hasCellular = NO;
    NSInteger expectedCallbackCount = 2;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = @"www.baidu.com";
    request.nameServer = @"114.114.114.114";
    request.appKey = kTestAppKey;
    request.timeout = 5000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = YES;
    request.detectEx = @{@"case_id": @"DNS-015", @"test_scene": @"multi_network_types"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
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

/// 【DNS-016】对比测试 enableMultiplePortsDetect=false 和 true 的行为差异
/// 验证点：false=1次回调(单网卡), true=2次回调且包含Wi-Fi和蜂窝网络
- (void)testDnsMultiplePortsCompare {
    NSLog(@"🧪 开始执行用例DNS-016：多网卡参数对比测试");
    NSLog(@"⚠️ 注意：此测试需要设备同时开启Wi-Fi和蜂窝数据以观察差异");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-多网卡对比"];
    
    __block NSInteger falseCallbackCount = 0;
    __block NSInteger trueCallbackCount = 0;
    __block NSMutableSet<NSString *> *falseNetworkTypes = [NSMutableSet set];
    __block NSMutableSet<NSString *> *trueNetworkTypes = [NSMutableSet set];
    __block BOOL trueHasWiFi = NO;
    __block BOOL trueHasCellular = NO;
    __block BOOL trueExpectationFulfilled = NO;
    NSInteger expectedTrueCallbackCount = 2;
    
    // 第一阶段：enableMultiplePortsDetect = NO
    CLSDnsRequest *request1 = [[CLSDnsRequest alloc] init];
    request1.domain = kTestDomain;
    request1.nameServer = @"114.114.114.114";
    request1.appKey = kTestAppKey;
    request1.timeout = 10000;  // 10秒，单位ms
    request1.enableMultiplePortsDetect = NO;
    request1.detectEx = @{@"case_id": @"DNS-016-false"};
    
    [self.diagnosis dns:request1 complate:^(CLSResponse *response) {
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
        CLSDnsRequest *request2 = [[CLSDnsRequest alloc] init];
        request2.domain = kTestDomain;
        request2.nameServer = @"114.114.114.114";
        request2.appKey = kTestAppKey;
        request2.timeout = 10000;  // 10秒，单位ms
        request2.enableMultiplePortsDetect = YES;
        request2.detectEx = @{@"case_id": @"DNS-016-true"};
        
        [self.diagnosis dns:request2 complate:^(CLSResponse *response) {
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

#pragma mark - IPv6 DNS服务器测试

/// 【DNS-017】验证IPv6 DNS服务器 - 谷歌公共DNS
- (void)testDnsIPv6ServerGoogle {
    NSLog(@"🧪 开始执行用例DNS-017：IPv6 DNS服务器验证 - 谷歌DNS");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-IPv6服务器-Google"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"2001:4860:4860::8888";  // Google IPv6 DNS
    request.appKey = kTestAppKey;
    request.timeout = 15000;  // 15秒，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-017", @"dns_server_type": @"IPv6", @"provider": @"Google"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS IPv6服务器(Google)验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 验证使用的是IPv6 DNS服务器
            NSString *hostIP = origin[@"host_ip"];
            XCTAssertNotNil(hostIP, @"host_ip不应为空");
            XCTAssertTrue([self isIPv6Address:hostIP], @"host_ip应为IPv6地址，实际: %@", hostIP);
            NSLog(@"✅ 使用IPv6 DNS服务器: %@", hostIP);
            
            // 验证DNS解析成功
            XCTAssertEqualObjects(origin[@"status"], @"NOERROR", @"DNS解析应成功");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【DNS-018】验证IPv6 DNS服务器 - Cloudflare公共DNS
- (void)testDnsIPv6ServerCloudflare {
    NSLog(@"🧪 开始执行用例DNS-018：IPv6 DNS服务器验证 - Cloudflare DNS");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-IPv6服务器-Cloudflare"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"2606:4700:4700::1111";  // Cloudflare IPv6 DNS
    request.appKey = kTestAppKey;
    request.timeout = 15000;  // 15秒，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-018", @"dns_server_type": @"IPv6", @"provider": @"Cloudflare"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS IPv6服务器(Cloudflare)验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 验证使用的是IPv6 DNS服务器
            NSString *hostIP = origin[@"host_ip"];
            XCTAssertNotNil(hostIP, @"host_ip不应为空");
            XCTAssertTrue([self isIPv6Address:hostIP], @"host_ip应为IPv6地址，实际: %@", hostIP);
            NSLog(@"✅ 使用IPv6 DNS服务器: %@", hostIP);
            
            // 验证DNS解析成功
            XCTAssertEqualObjects(origin[@"status"], @"NOERROR", @"DNS解析应成功");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【DNS-019】验证IPv6 DNS服务器 - 阿里云公共DNS
- (void)testDnsIPv6ServerAliyun {
    NSLog(@"🧪 开始执行用例DNS-019：IPv6 DNS服务器验证 - 阿里云DNS");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-IPv6服务器-Aliyun"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    request.nameServer = @"2400:3200::1";  // 阿里云 IPv6 DNS
    request.appKey = kTestAppKey;
    request.timeout = 15000;  // 15秒，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-019", @"dns_server_type": @"IPv6", @"provider": @"Aliyun"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS IPv6服务器(阿里云)验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 验证使用的是IPv6 DNS服务器
            NSString *hostIP = origin[@"host_ip"];
            XCTAssertNotNil(hostIP, @"host_ip不应为空");
            XCTAssertTrue([self isIPv6Address:hostIP], @"host_ip应为IPv6地址，实际: %@", hostIP);
            NSLog(@"✅ 使用IPv6 DNS服务器: %@", hostIP);
            
            // 验证DNS解析成功
            XCTAssertEqualObjects(origin[@"status"], @"NOERROR", @"DNS解析应成功");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【DNS-020】验证IPv6 DNS服务器 - 多服务器混合（IPv4 + IPv6）
- (void)testDnsIPv6ServerMixed {
    NSLog(@"🧪 开始执行用例DNS-020：混合DNS服务器验证（IPv4 + IPv6）");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-混合服务器"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = kTestDomain;
    // 混合使用IPv4和IPv6 DNS服务器
    request.nameServer = @"114.114.114.114,2001:4860:4860::8888";
    request.appKey = kTestAppKey;
    request.timeout = 15000;  // 15秒，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-020", @"dns_server_type": @"Mixed"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS混合服务器验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 验证使用了其中一个DNS服务器
            NSString *hostIP = origin[@"host_ip"];
            XCTAssertNotNil(hostIP, @"host_ip不应为空");
            NSLog(@"📍 使用的DNS服务器: %@", hostIP);
            
            // 验证DNS解析成功
            XCTAssertEqualObjects(origin[@"status"], @"NOERROR", @"DNS解析应成功");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

/// 【DNS-021】验证IPv6 DNS服务器查询AAAA记录
- (void)testDnsIPv6ServerQueryAAAA {
    NSLog(@"🧪 开始执行用例DNS-021：IPv6 DNS服务器查询AAAA记录");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-IPv6服务器-AAAA"];
    __block BOOL fulfilled = NO;
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = @"www.baidu.com";  // 使用有IPv6记录的域名
    request.nameServer = @"2001:4860:4860::8888";  // Google IPv6 DNS
    request.appKey = kTestAppKey;
    request.prefer = 3;  // IPv6 Only - 只查询AAAA记录
    request.timeout = 15000;  // 15秒，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"DNS-021", @"dns_server_type": @"IPv6", @"query_type": @"AAAA"};
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"DNS IPv6服务器查询AAAA记录结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 验证使用的是IPv6 DNS服务器
            NSString *hostIP = origin[@"host_ip"];
            XCTAssertNotNil(hostIP, @"host_ip不应为空");
            XCTAssertTrue([self isIPv6Address:hostIP], @"host_ip应为IPv6地址，实际: %@", hostIP);
            
            // 验证ANSWER中的记录类型（如果有解析结果）
            id answerObj = origin[@"ANSWER"];
            if (answerObj && [answerObj isKindOfClass:[NSString class]]) {
                NSString *answer = (NSString *)answerObj;
                if (answer.length > 0) {
                    NSLog(@"📍 ANSWER: %@", answer);
                    // AAAA记录应包含IPv6地址
                }
            } else if (answerObj) {
                NSLog(@"📍 ANSWER (非字符串类型): %@", answerObj);
            }
            
            NSLog(@"✅ IPv6 DNS服务器查询AAAA记录完成");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

//#pragma mark - DNS-022: 高频次并发探测测试
//
///**
// * DNS-022: 高频次并发探测 - 短时间内发起大量探测请求
// * 验证SDK在高并发场景下的稳定性和正确性
// */
//- (void)testDnsHighFrequencyConcurrentDetection {
//    NSLog(@"========== DNS-022: 高频次并发探测测试 ==========");
//    
//    const NSInteger totalRequests = 20;  // 总请求数
//    __block NSInteger completedCount = 0;
//    __block NSInteger successCount = 0;
//    __block NSInteger failCount = 0;
//    
//    XCTestExpectation *expectation = [self expectationWithDescription:@"高频次DNS探测完成"];
//    
//    // 用于同步计数
//    NSObject *lock = [[NSObject alloc] init];
//    
//    // 测试用的多个域名
//    NSArray *domains = @[
//        @"www.baidu.com",
//        @"www.qq.com",
//        @"www.taobao.com",
//        @"www.jd.com",
//        @"www.163.com"
//    ];
//    
//    // 多个DNS服务器
//    NSArray *dnsServers = @[
//        @"114.114.114.114",
//        @"8.8.8.8",
//        @"223.5.5.5",
//        @"119.29.29.29"
//    ];
//    
//    NSDate *startTime = [NSDate date];
//    NSLog(@"📍 开始发起 %ld 个并发DNS探测请求...", (long)totalRequests);
//    
//    for (NSInteger i = 0; i < totalRequests; i++) {
//        CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
//        request.domain = domains[i % domains.count];
//        request.nameServer = dnsServers[i % dnsServers.count];
//        request.appKey = kTestAppKey;
//        request.timeout = 10000;  // 10秒，单位ms
//        request.enableMultiplePortsDetect = NO;
//        request.detectEx = @{
//            @"case_id": @"DNS-022",
//            @"request_index": @(i),
//            @"test_type": @"high_frequency"
//        };
//        
//        [self.diagnosis dns:request complate:^(CLSResponse *response) {
//            @synchronized (lock) {
//                completedCount++;
//                
//                BOOL isSuccess = NO;
//                @try {
//                    NSDictionary *data = [self parseResponseContent:response];
//                    NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
//                    NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
//                    
//                    NSString *hostIP = origin[@"host_ip"];
//                    if (hostIP && hostIP.length > 0) {
//                        isSuccess = YES;
//                    }
//                } @catch (NSException *exception) {
//                    NSLog(@"⚠️ 请求#%ld 解析异常: %@", (long)completedCount, exception.reason);
//                }
//                
//                if (isSuccess) {
//                    successCount++;
//                } else {
//                    failCount++;
//                }
//                
//                // 每5个请求输出一次进度
//                if (completedCount % 5 == 0 || completedCount == totalRequests) {
//                    NSLog(@"📊 进度: %ld/%ld (成功: %ld, 失败: %ld)", 
//                          (long)completedCount, (long)totalRequests, (long)successCount, (long)failCount);
//                }
//                
//                // 所有请求完成
//                if (completedCount == totalRequests) {
//                    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startTime];
//                    NSLog(@"========== 高频次探测测试完成 ==========");
//                    NSLog(@"📍 总请求数: %ld", (long)totalRequests);
//                    NSLog(@"📍 成功数: %ld", (long)successCount);
//                    NSLog(@"📍 失败数: %ld", (long)failCount);
//                    NSLog(@"📍 成功率: %.1f%%", (successCount * 100.0 / totalRequests));
//                    NSLog(@"📍 总耗时: %.2f秒", duration);
//                    NSLog(@"📍 平均每秒处理: %.1f个请求", totalRequests / duration);
//                    
//                    // 验证成功率至少80%
//                    XCTAssertGreaterThanOrEqual(successCount, totalRequests * 0.8, 
//                        @"成功率应至少80%%, 实际: %.1f%%", (successCount * 100.0 / totalRequests));
//                    
//                    [expectation fulfill];
//                }
//            }
//        }];
//    }
//    
//    [self waitForExpectationsWithTimeout:60 handler:^(NSError *error) {
//        if (error) {
//            NSLog(@"❌ 高频次探测测试超时: 完成 %ld/%ld", (long)completedCount, (long)totalRequests);
//        }
//    }];
//}
//
//#pragma mark - DNS-023: 极限并发测试
//
///**
// * DNS-023: 极限并发探测 - 同时发起50个请求测试SDK极限性能
// */
//- (void)testDnsExtremeConcurrentDetection {
//    NSLog(@"========== DNS-023: 极限并发探测测试 ==========");
//    
//    const NSInteger totalRequests = 50;
//    __block NSInteger completedCount = 0;
//    __block NSInteger successCount = 0;
//    
//    XCTestExpectation *expectation = [self expectationWithDescription:@"极限并发DNS探测完成"];
//    NSObject *lock = [[NSObject alloc] init];
//    
//    NSDate *startTime = [NSDate date];
//    NSLog(@"📍 开始发起 %ld 个极限并发DNS探测请求...", (long)totalRequests);
//    
//    for (NSInteger i = 0; i < totalRequests; i++) {
//        CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
//        request.domain = @"www.baidu.com";
//        request.nameServer = @"114.114.114.114";
//        request.appKey = kTestAppKey;
//        request.timeout = 15000;  // 15秒，单位ms
//        request.enableMultiplePortsDetect = NO;
//        request.detectEx = @{
//            @"case_id": @"DNS-023",
//            @"request_index": @(i),
//            @"test_type": @"extreme_concurrent"
//        };
//        
//        [self.diagnosis dns:request complate:^(CLSResponse *response) {
//            @synchronized (lock) {
//                completedCount++;
//                
//                @try {
//                    NSDictionary *data = [self parseResponseContent:response];
//                    NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
//                    NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
//                    
//                    if (origin[@"host_ip"]) {
//                        successCount++;
//                    }
//                } @catch (NSException *exception) {
//                    // 忽略解析异常
//                }
//                
//                if (completedCount == totalRequests) {
//                    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startTime];
//                    NSLog(@"========== 极限并发测试完成 ==========");
//                    NSLog(@"📍 总请求: %ld, 成功: %ld, 耗时: %.2fs", 
//                          (long)totalRequests, (long)successCount, duration);
//                    NSLog(@"📍 吞吐量: %.1f req/s", totalRequests / duration);
//                    
//                    // 极限测试允许更低的成功率（70%）
//                    XCTAssertGreaterThanOrEqual(successCount, totalRequests * 0.7,
//                        @"极限并发成功率应至少70%%");
//                    
//                    [expectation fulfill];
//                }
//            }
//        }];
//    }
//    
//    [self waitForExpectationsWithTimeout:90 handler:nil];
//}
//
//#pragma mark - DNS-024: 快速连续探测测试
//
///**
// * DNS-024: 快速连续探测 - 模拟用户快速重复点击场景
// */
//- (void)testDnsRapidSequentialDetection {
//    NSLog(@"========== DNS-024: 快速连续探测测试 ==========");
//    
//    const NSInteger totalRequests = 10;
//    __block NSInteger completedCount = 0;
//    __block NSMutableArray<NSNumber *> *responseTimes = [NSMutableArray array];
//    
//    XCTestExpectation *expectation = [self expectationWithDescription:@"快速连续DNS探测完成"];
//    NSObject *lock = [[NSObject alloc] init];
//    
//    NSLog(@"📍 开始快速连续发起 %ld 个DNS探测请求（间隔100ms）...", (long)totalRequests);
//    
//    for (NSInteger i = 0; i < totalRequests; i++) {
//        // 每100ms发起一个请求，模拟快速点击
//        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 100 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
//            NSDate *requestStart = [NSDate date];
//            
//            CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
//            request.domain = @"www.qq.com";
//            request.nameServer = @"119.29.29.29";
//            request.appKey = kTestAppKey;
//            request.timeout = 10;
//            request.enableMultiplePortsDetect = NO;
//            request.detectEx = @{
//                @"case_id": @"DNS-024",
//                @"request_index": @(i),
//                @"test_type": @"rapid_sequential"
//            };
//            
//            [self.diagnosis dns:request complate:^(CLSResponse *response) {
//                NSTimeInterval responseTime = [[NSDate date] timeIntervalSinceDate:requestStart] * 1000;
//                
//                @synchronized (lock) {
//                    completedCount++;
//                    [responseTimes addObject:@(responseTime)];
//                    
//                    NSLog(@"📍 请求#%ld 完成，响应时间: %.0fms", (long)completedCount, responseTime);
//                    
//                    if (completedCount == totalRequests) {
//                        // 计算统计数据
//                        double totalTime = 0;
//                        double minTime = INFINITY;
//                        double maxTime = 0;
//                        
//                        for (NSNumber *time in responseTimes) {
//                            double t = time.doubleValue;
//                            totalTime += t;
//                            minTime = MIN(minTime, t);
//                            maxTime = MAX(maxTime, t);
//                        }
//                        
//                        double avgTime = totalTime / responseTimes.count;
//                        
//                        NSLog(@"========== 快速连续探测统计 ==========");
//                        NSLog(@"📍 平均响应时间: %.0fms", avgTime);
//                        NSLog(@"📍 最小响应时间: %.0fms", minTime);
//                        NSLog(@"📍 最大响应时间: %.0fms", maxTime);
//                        
//                        // 验证平均响应时间在合理范围内（5秒内）
//                        XCTAssertLessThan(avgTime, 5000, @"平均响应时间应小于5秒");
//                        
//                        [expectation fulfill];
//                    }
//                }
//            }];
//        });
//    }
//    
//    [self waitForExpectationsWithTimeout:30 handler:nil];
//}

@end
