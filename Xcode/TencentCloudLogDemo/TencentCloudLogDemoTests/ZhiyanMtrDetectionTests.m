#import "CLSNetworkDiagnosisBaseTests.h"

@interface ZhiyanMtrDetectionTests : CLSNetworkDiagnosisBaseTests
@end

@implementation ZhiyanMtrDetectionTests

#pragma mark - 基本功能测试

/// 【MTR-001】验证MTR探测基本功能及所有字段完整性
- (void)testMtrBasicFunctionality {
    NSLog(@"🧪 开始执行用例MTR-001：MTR探测基本功能验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR基本功能"];
    __block BOOL fulfilled = NO;
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.maxTTL = 30;
    request.timeout = 10000;  // 10秒，单位ms
    request.protocol = @"icmp";
    request.pageName = @"mtr_test_page";
    request.enableMultiplePortsDetect = NO;  // 基本测试使用单网卡模式
    request.detectEx = @{@"case_id": @"MTR-001", @"priority": @"P0"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR基本功能验证结果"];
            
            // 1. 公共字段校验
            [self validateCommonFields:data];
            [self validateResourceFields:data];
            [self validateAttributeFields:data expectedType:@"mtr"];
            [self validateNetOriginFields:data expectedMethod:@"mtr"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            // 2. MTR专用字段校验
            [self validateMtrOriginFields:origin];
            
            // 3. paths数组校验
            NSArray *paths = [self safeConvertToArray:origin[@"paths"]];
            [self validateMtrPathsFields:paths expectedProtocol:@"icmp"];
            
            // 4. 网络环境信息校验
            [self validateNetInfo:[self safeConvertToDictionary:origin[@"netInfo"]]];
            
            // 5. 扩展字段校验
            [self validateExtensionFields:origin
                         expectedDetectEx:@{@"case_id": @"MTR-001"}];
            
            // 6. 全局 userEx 字段校验（验证 setUserEx 设置成功）
            [self validateUserExFields:origin expectedUserEx:nil];
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
}

#pragma mark - 参数验证测试

/// 【MTR-002】验证domain参数
- (void)testMtrDomainParameter {
    NSLog(@"🧪 开始执行用例MTR-002：domain参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-domain"];
    __block BOOL fulfilled = NO;
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = @"www.tencentcloud.com";
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.maxTTL = 20;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = NO;
    request.detectEx = @{@"case_id": @"MTR-002"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR domain验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertEqualObjects(origin[@"host"], @"www.tencentcloud.com", @"host应匹配设置的domain");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
}

/// 【MTR-003】验证protocol参数 - ICMP
- (void)testMtrProtocolICMP {
    NSLog(@"🧪 开始执行用例MTR-003：protocol参数验证 - ICMP");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-protocol-icmp"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = @"www.tencent.com";
    request.appKey = kTestAppKey;
    request.maxTimes = 10;
    request.maxTTL = 30;
    request.timeout = 2000;  // 2秒，单位ms
    request.protocol = @"icmp";
    request.prefer = 0;  // IPv4优先
    request.detectEx = @{@"case_id": @"MTR-003"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR ICMP验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            NSArray *paths = [self safeConvertToArray:origin[@"paths"]];
            
            if (paths.count > 0) {
                NSDictionary *firstPath = [self safeConvertToDictionary:paths.firstObject];
                NSString *protocol = firstPath[@"protocol"];
                NSLog(@"📍 ICMP模式 - 实际协议: %@", protocol);
            }
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
}

/// 【MTR-004】验证protocol参数 - UDP
- (void)testMtrProtocolUDP {
    NSLog(@"🧪 开始执行用例MTR-004：protocol参数验证 - UDP");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-protocol-udp"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = @"www.tencent.com";
    request.appKey = kTestAppKey;
    request.maxTimes = 10;
    request.maxTTL = 30;
    request.timeout = 10000;  // 10秒，单位ms
    request.protocol = @"udp";
    request.detectEx = @{@"case_id": @"MTR-004"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR UDP验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            NSArray *paths = [self safeConvertToArray:origin[@"paths"]];
            
            if (paths.count > 0) {
                NSDictionary *firstPath = [self safeConvertToDictionary:paths.firstObject];
                NSString *protocol = firstPath[@"protocol"];
                NSLog(@"📍 UDP模式 - 实际协议: %@", protocol);
            }
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
}

/// 【MTR-005】验证protocol参数 - TCP
- (void)testMtrProtocolTCP {
    NSLog(@"🧪 开始执行用例MTR-005：protocol参数验证 - TCP");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-protocol-tcp"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 10;
    request.maxTTL = 30;
    request.timeout = 10000;  // 10秒，单位ms
    request.protocol = @"tcp";
    request.detectEx = @{@"case_id": @"MTR-005"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR TCP验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            NSArray *paths = [self safeConvertToArray:origin[@"paths"]];
            
            if (paths.count > 0) {
                NSDictionary *firstPath = [self safeConvertToDictionary:paths.firstObject];
                NSString *protocol = firstPath[@"protocol"];
                NSLog(@"📍 TCP模式 - 实际协议: %@", protocol);
            }
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
}

/// 【MTR-006】验证maxTTL参数
- (void)testMtrMaxTTLParameter {
    NSLog(@"🧪 开始执行用例MTR-006：maxTTL参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-maxTTL"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.maxTTL = 10;  // 限制最大跳数为10
    request.timeout = 10000;  // 10秒，单位ms
    request.detectEx = @{@"case_id": @"MTR-006"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR maxTTL验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            NSArray *paths = [self safeConvertToArray:origin[@"paths"]];
            
            if (paths.count > 0) {
                NSDictionary *firstPath = [self safeConvertToDictionary:paths.firstObject];
                NSArray *result = [self safeConvertToArray:firstPath[@"result"]];
                NSLog(@"📍 maxTTL=10时，实际跳数: %lu", (unsigned long)result.count);
                XCTAssertLessThanOrEqual(result.count, 10, @"跳数不应超过maxTTL");
            }
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
}

/// 【MTR-007】验证maxTimes参数
- (void)testMtrMaxTimesParameter {
    NSLog(@"🧪 开始执行用例MTR-007：maxTimes参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-maxTimes"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 5;  // 每跳探测5次
    request.maxTTL = 10;
    request.timeout = 10000;  // 10秒，单位ms
    request.detectEx = @{@"case_id": @"MTR-007"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR maxTimes验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertNotNil(origin, @"origin不应为空");
            NSLog(@"📍 maxTimes=5设置完成");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
}

/// 【MTR-008】验证timeout参数
- (void)testMtrTimeoutParameter {
    NSLog(@"🧪 开始执行用例MTR-008：timeout参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-timeout"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = @"192.0.2.1";  // 不可达IP
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.maxTTL = 5;
    request.timeout = 5000;  // 5秒超时，单位ms
    request.detectEx = @{@"case_id": @"MTR-008"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR timeout验证结果"];
            
            // 超时也应返回数据
            XCTAssertNotNil(data, @"超时也应返回数据");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:30 handler:nil];
}

/// 【MTR-009】验证enableMultiplePortsDetect参数
- (void)testMtrEnableMultiplePortsDetect {
    NSLog(@"🧪 开始执行用例MTR-009：enableMultiplePortsDetect参数验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-multiPorts"];
    __block BOOL fulfilled = NO;
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.maxTTL = 10;
    request.timeout = 10000;  // 10秒，单位ms
    request.enableMultiplePortsDetect = YES;
    request.detectEx = @{@"case_id": @"MTR-009"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        if (fulfilled) return;
        fulfilled = YES;
        
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR multiPorts验证结果"];
            
            [self validateCommonFields:data];
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
}

/// 【MTR-010】验证detectEx扩展字段
- (void)testMtrExtensionFields {
    NSLog(@"🧪 开始执行用例MTR-010：扩展字段验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-extension"];
    
    NSDictionary *detectEx = @{
        @"case_id": @"MTR-010",
        @"mtr_scene": @"network_diagnose",
        @"priority": @"P1"
    };
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.maxTTL = 10;
    request.timeout = 10000;  // 10秒，单位ms
    request.pageName = @"mtr_test_page";
    request.detectEx = detectEx;
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR扩展字段验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            
            XCTAssertEqualObjects(attribute[@"page.name"], @"mtr_test_page", @"page.name应匹配");
            [self validateExtensionFields:origin expectedDetectEx:detectEx];
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
}

#pragma mark - 字段完整性测试

/// 【MTR-011】验证所有返回字段完整性
- (void)testMtrAllFieldsCompleteness {
    NSLog(@"🧪 开始执行用例MTR-011：字段完整性验证");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-字段完整性"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 3;
    request.maxTTL = 20;
    request.timeout = 10000;  // 10秒，单位ms
    request.protocol = @"icmp";
    request.pageName = @"mtr_fields_test";
    request.detectEx = @{@"case_id": @"MTR-011"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR字段完整性验证结果"];
            
            // 1. 公共字段
            [self validateCommonFields:data];
            [self validateResourceFields:data];
            
            // 2. Attribute字段
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            XCTAssertEqualObjects(attribute[@"net.type"], @"mtr", @"net.type应为mtr");
            
            // 3. net.origin字段
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            [self validateMtrOriginFields:origin];
            
            // 4. 验证src字段
            XCTAssertEqualObjects(origin[@"src"], @"app", @"src应为app");
            
            // 5. paths字段
            NSArray *paths = [self safeConvertToArray:origin[@"paths"]];
            XCTAssertNotNil(paths, @"应包含paths数组");
            XCTAssertNotNil(origin[@"trace_id"], @"origin应包含trace_id");
            
            if (paths.count > 0) {
                NSDictionary *firstPath = [self safeConvertToDictionary:paths.firstObject];
                XCTAssertNotNil(firstPath[@"method"], @"path应包含method");
                XCTAssertNotNil(firstPath[@"host"], @"path应包含host");
                XCTAssertNotNil(firstPath[@"host_ip"], @"path应包含host_ip");
                XCTAssertNotNil(firstPath[@"type"], @"path应包含type");
                XCTAssertNotNil(firstPath[@"path"], @"path应包含path标识");
                
                // 验证result数组中的跳数信息
                NSArray *result = [self safeConvertToArray:firstPath[@"result"]];
                if (result.count > 0) {
                    NSDictionary *firstHop = [self safeConvertToDictionary:result.firstObject];
                    [self validateMtrHopFields:firstHop];
                }
            }
            
            // 6. netInfo字段
            [self validateNetInfo:[self safeConvertToDictionary:origin[@"netInfo"]]];
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
}

#pragma mark - IP协议偏好测试

/// 【MTR-012】验证prefer参数 - IPv4优先 (prefer=0)
- (void)testMtrPreferIPv4First {
    NSLog(@"🧪 开始执行用例MTR-012：prefer参数验证 - IPv4优先");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-prefer-IPv4优先"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.maxTTL = 10;
    request.timeout = 30000;  // 30秒，单位ms
    request.prefer = 0;  // IPv4优先
    request.detectEx = @{@"case_id": @"MTR-012", @"prefer_mode": @"IPv4优先"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR IPv4优先验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            NSArray *paths = [self safeConvertToArray:origin[@"paths"]];
            
            if (paths.count > 0) {
                NSDictionary *firstPath = [self safeConvertToDictionary:paths.firstObject];
                NSString *hostIP = firstPath[@"host_ip"];
                XCTAssertNotNil(hostIP, @"host_ip不应为空");
                NSLog(@"📍 IPv4优先模式 - host_ip: %@", hostIP);
                
                if ([self isIPv4Address:hostIP]) {
                    NSLog(@"✅ 返回IPv4地址: %@", hostIP);
                } else if ([self isIPv6Address:hostIP]) {
                    NSLog(@"ℹ️ 返回IPv6地址（可能无IPv4）: %@", hostIP);
                }
            }
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
}

/// 【MTR-013】验证prefer参数 - IPv6优先 (prefer=1)
- (void)testMtrPreferIPv6First {
    NSLog(@"🧪 开始执行用例MTR-013：prefer参数验证 - IPv6优先");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-prefer-IPv6优先"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.maxTTL = 10;
    request.timeout = 30000;  // 30秒，单位ms
    request.prefer = 1;  // IPv6优先
    request.detectEx = @{@"case_id": @"MTR-013", @"prefer_mode": @"IPv6优先"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR IPv6优先验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            NSArray *paths = [self safeConvertToArray:origin[@"paths"]];
            
            if (paths.count > 0) {
                NSDictionary *firstPath = [self safeConvertToDictionary:paths.firstObject];
                NSString *hostIP = firstPath[@"host_ip"];
                XCTAssertNotNil(hostIP, @"host_ip不应为空");
                NSLog(@"📍 IPv6优先模式 - host_ip: %@", hostIP);
                
                if ([self isIPv6Address:hostIP]) {
                    NSLog(@"✅ 返回IPv6地址: %@", hostIP);
                } else if ([self isIPv4Address:hostIP]) {
                    NSLog(@"ℹ️ 返回IPv4地址（可能无IPv6）: %@", hostIP);
                }
            }
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
}

/// 【MTR-014】验证prefer参数 - IPv4 Only (prefer=2)
- (void)testMtrPreferIPv4Only {
    NSLog(@"🧪 开始执行用例MTR-014：prefer参数验证 - IPv4 Only");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-prefer-IPv4Only"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.maxTTL = 10;
    request.timeout = 30000;  // 30秒，单位ms
    request.prefer = 2;  // IPv4 Only
    request.detectEx = @{@"case_id": @"MTR-014", @"prefer_mode": @"IPv4Only"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR IPv4 Only验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            NSArray *paths = [self safeConvertToArray:origin[@"paths"]];
            
            if (paths.count > 0) {
                NSDictionary *firstPath = [self safeConvertToDictionary:paths.firstObject];
                NSString *hostIP = firstPath[@"host_ip"];
                XCTAssertNotNil(hostIP, @"host_ip不应为空");
                NSLog(@"📍 IPv4 Only模式 - host_ip: %@", hostIP);
                
                XCTAssertTrue([self isIPv4Address:hostIP], @"IPv4 Only模式应返回IPv4地址，实际: %@", hostIP);
                NSLog(@"✅ IPv4 Only验证通过: %@", hostIP);
            }
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
}

/// 【MTR-015】验证prefer参数 - IPv6 Only (prefer=3)
- (void)testMtrPreferIPv6Only {
    NSLog(@"🧪 开始执行用例MTR-015：prefer参数验证 - IPv6 Only");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-prefer-IPv6Only"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = @"ipv6.google.com";  // 使用支持IPv6的域名
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.maxTTL = 10;
    request.timeout = 30000;  // 30秒，单位ms
    request.prefer = 3;  // IPv6 Only
    request.detectEx = @{@"case_id": @"MTR-015", @"prefer_mode": @"IPv6Only"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR IPv6 Only验证结果"];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            NSArray *paths = [self safeConvertToArray:origin[@"paths"]];
            
            if (paths.count > 0) {
                NSDictionary *firstPath = [self safeConvertToDictionary:paths.firstObject];
                NSString *hostIP = firstPath[@"host_ip"];
                XCTAssertNotNil(hostIP, @"host_ip不应为空");
                NSLog(@"📍 IPv6 Only模式 - host_ip: %@", hostIP);
                
                XCTAssertTrue([self isIPv6Address:hostIP], @"IPv6 Only模式应返回IPv6地址，实际: %@", hostIP);
                NSLog(@"✅ IPv6 Only验证通过: %@", hostIP);
            }
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
}

#pragma mark - 异常场景测试

/// 【MTR-ERR-001】异常场景 - 无效域名
- (void)testMtrInvalidDomain {
    NSLog(@"🧪 开始执行用例MTR-ERR-001：无效域名");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR无效域名"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = @"invalid.domain.not.exist.test";
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.maxTTL = 5;
    request.timeout = 10000;  // 10秒，单位ms
    request.detectEx = @{@"case_id": @"MTR-ERR-001"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR无效域名结果"];
            
            XCTAssertNotNil(data, @"无效域名也应有返回数据");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:30 handler:nil];
}

/// 【MTR-ERR-002】异常场景 - 不可达IP
- (void)testMtrUnreachableIP {
    NSLog(@"🧪 开始执行用例MTR-ERR-002：不可达IP");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR不可达IP"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = @"192.0.2.1";  // 不可达IP
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.maxTTL = 5;
    request.timeout = 10000;  // 10秒，单位ms
    request.detectEx = @{@"case_id": @"MTR-ERR-002"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR不可达IP结果"];
            
            XCTAssertNotNil(data, @"不可达IP也应有返回数据");
            
        } @catch (NSException *exception) {
            XCTFail(@"测试执行异常：%@", exception.reason);
        } @finally {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:30 handler:nil];
}

#pragma mark - 多网卡环境测试

/// 【MTR-016】验证多网卡探测 - Wi-Fi和蜂窝网络环境下的完整行为
/// 注意：此测试需要在同时连接Wi-Fi和蜂窝网络的设备上运行
/// 验证点：1. 回调次数=2  2. 必须同时检测到Wi-Fi和4G/蜂窝网络类型
- (void)testMtrMultiplePortsWithNetworkType {
    NSLog(@"🧪 开始执行用例MTR-016：多网卡探测网络环境验证");
    NSLog(@"⚠️ 注意：此测试需要设备同时开启Wi-Fi和蜂窝数据");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-多网卡网络环境"];
    
    __block NSMutableArray<NSString *> *detectedNetworks = [NSMutableArray array];
    __block NSMutableArray<NSString *> *detectedInterfaces = [NSMutableArray array];
    __block NSInteger callbackCount = 0;
    __block BOOL expectationFulfilled = NO;
    __block BOOL hasWiFi = NO;
    __block BOOL hasCellular = NO;
    NSInteger expectedCallbackCount = 2;  // 期望2次回调（Wi-Fi + 蜂窝）
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.maxTTL = 10;
    request.timeout = 15000;  // 15秒，单位ms
    request.enableMultiplePortsDetect = YES;  // 启用多网卡探测
    request.detectEx = @{@"case_id": @"MTR-016", @"test_scene": @"multi_port_network"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            callbackCount++;
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:[NSString stringWithFormat:@"MTR多网卡探测结果 #%ld", (long)callbackCount]];
            
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
            
            // 验证MTR特有字段
            NSArray *paths = [self safeConvertToArray:origin[@"paths"]];
            XCTAssertNotNil(paths, @"paths不应为空");
            
            // 验证interface字段（在paths[0]内部）
            NSString *interface = nil;
            if (paths.count > 0) {
                NSDictionary *firstPath = [self safeConvertToDictionary:paths.firstObject];
                interface = firstPath[@"interface"];
            }
            XCTAssertNotNil(interface, @"interface字段不应为空");
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
            
            NSLog(@"📊 MTR多网卡探测结果汇总:");
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
    
    [self waitForExpectationsWithTimeout:120 handler:^(NSError *error) {
        if (error) {
            NSLog(@"❌ 测试超时 - 总回调次数: %ld (期望: %ld)", (long)callbackCount, (long)expectedCallbackCount);
            NSLog(@"   - 检测到网络类型: %@", detectedNetworks);
            NSLog(@"   - Wi-Fi: %@, 蜂窝: %@", hasWiFi ? @"✅" : @"❌", hasCellular ? @"✅" : @"❌");
        }
    }];
}

/// 【MTR-017】验证当前网络环境识别（单网卡模式）
- (void)testMtrCurrentNetworkIdentification {
    NSLog(@"🧪 开始执行用例MTR-017：当前网络环境识别（单网卡）");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-网络识别"];
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.maxTTL = 10;
    request.timeout = 15000;  // 15秒，单位ms
    request.enableMultiplePortsDetect = NO;  // 单网卡探测
    request.detectEx = @{@"case_id": @"MTR-017", @"test_scene": @"network_identification"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            NSDictionary *data = [self parseResponseContent:response];
            [self logCompleteResult:data withTitle:@"MTR当前网络环境识别结果"];
            
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
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
}

/// 【MTR-018】验证多网卡探测产生多个网络类型结果
/// 验证点：必须同时检测到Wi-Fi和蜂窝网络(4G/5G等)
- (void)testMtrMultipleNetworkTypesDetection {
    NSLog(@"🧪 开始执行用例MTR-018：多网络类型探测");
    NSLog(@"⚠️ 注意：此测试需要设备同时开启Wi-Fi和蜂窝数据");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-多网络类型"];
    
    __block NSMutableSet<NSString *> *networkTypes = [NSMutableSet set];
    __block NSMutableSet<NSString *> *interfaces = [NSMutableSet set];
    __block NSInteger callbackCount = 0;
    __block BOOL expectationFulfilled = NO;
    __block BOOL hasWiFi = NO;
    __block BOOL hasCellular = NO;
    NSInteger expectedCallbackCount = 2;
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = @"www.baidu.com";
    request.appKey = kTestAppKey;
    request.maxTimes = 2;
    request.maxTTL = 10;
    request.timeout = 15000;  // 15秒，单位ms
    request.enableMultiplePortsDetect = YES;
    request.detectEx = @{@"case_id": @"MTR-018", @"test_scene": @"multi_network_types"};
    
    [self.diagnosis mtr:request complate:^(CLSResponse *response) {
        @try {
            callbackCount++;
            NSDictionary *data = [self parseResponseContent:response];
            
            NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
            NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
            NSDictionary *netInfo = [self safeConvertToDictionary:origin[@"netInfo"]];
            
            NSString *usedNet = netInfo[@"usedNet"];
            
            // interface在paths[0]内部
            NSArray *paths = [self safeConvertToArray:origin[@"paths"]];
            NSString *interface = nil;
            if (paths.count > 0) {
                NSDictionary *firstPath = [self safeConvertToDictionary:paths.firstObject];
                interface = firstPath[@"interface"];
            }
            
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
    
    [self waitForExpectationsWithTimeout:120 handler:^(NSError *error) {
        if (error) {
            NSLog(@"❌ 测试超时 - Wi-Fi: %@, 蜂窝: %@", hasWiFi ? @"✅" : @"❌", hasCellular ? @"✅" : @"❌");
        }
    }];
}

/// 【MTR-019】对比测试 enableMultiplePortsDetect=false 和 true 的行为差异
/// 验证点：false=1次回调(单网卡), true=2次回调且包含Wi-Fi和蜂窝网络
- (void)testMtrMultiplePortsCompare {
    NSLog(@"🧪 开始执行用例MTR-019：多网卡参数对比测试");
    NSLog(@"⚠️ 注意：此测试需要设备同时开启Wi-Fi和蜂窝数据以观察差异");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"MTR-多网卡对比"];
    
    __block NSInteger falseCallbackCount = 0;
    __block NSInteger trueCallbackCount = 0;
    __block NSMutableSet<NSString *> *falseNetworkTypes = [NSMutableSet set];
    __block NSMutableSet<NSString *> *trueNetworkTypes = [NSMutableSet set];
    __block BOOL trueHasWiFi = NO;
    __block BOOL trueHasCellular = NO;
    __block BOOL trueExpectationFulfilled = NO;
    NSInteger expectedTrueCallbackCount = 2;
    
    // 第一阶段：enableMultiplePortsDetect = NO
    CLSMtrRequest *request1 = [[CLSMtrRequest alloc] init];
    request1.domain = kTestDomain;
    request1.appKey = kTestAppKey;
    request1.maxTimes = 2;
    request1.maxTTL = 8;
    request1.timeout = 15000;  // 15秒，单位ms
    request1.enableMultiplePortsDetect = NO;
    request1.detectEx = @{@"case_id": @"MTR-019-false"};
    
    [self.diagnosis mtr:request1 complate:^(CLSResponse *response) {
        falseCallbackCount++;
        NSDictionary *data = [self parseResponseContent:response];
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        NSDictionary *netInfo = [self safeConvertToDictionary:origin[@"netInfo"]];
        NSString *usedNet = netInfo[@"usedNet"];
        if (usedNet) [falseNetworkTypes addObject:usedNet];
        NSLog(@"📍 enableMultiplePortsDetect=false 回调#%ld, usedNet: %@", (long)falseCallbackCount, usedNet);
    }];
    
    // 等待第一阶段完成后进行第二阶段（MTR耗时较长）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"📍 第一阶段完成，开始第二阶段测试");
        
        // 第二阶段：enableMultiplePortsDetect = YES
        CLSMtrRequest *request2 = [[CLSMtrRequest alloc] init];
        request2.domain = kTestDomain;
        request2.appKey = kTestAppKey;
        request2.maxTimes = 2;
        request2.maxTTL = 8;
        request2.timeout = 15000;  // 15秒，单位ms
        request2.enableMultiplePortsDetect = YES;
        request2.detectEx = @{@"case_id": @"MTR-019-true"};
        
        [self.diagnosis mtr:request2 complate:^(CLSResponse *response) {
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
    
    [self waitForExpectationsWithTimeout:180 handler:^(NSError *error) {
        if (error) {
            NSLog(@"❌ 测试超时");
            NSLog(@"   - false模式回调: %ld次", (long)falseCallbackCount);
            NSLog(@"   - true模式回调: %ld次 (期望: %ld)", (long)trueCallbackCount, (long)expectedTrueCallbackCount);
            NSLog(@"   - Wi-Fi: %@, 蜂窝: %@", trueHasWiFi ? @"✅" : @"❌", trueHasCellular ? @"✅" : @"❌");
        }
    }];
}

@end

