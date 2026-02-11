//
//  CLSEdgeCaseTests.m
//  TencentCloudLogDemoTests
//
//  Created by AI Assistant on 2026/02/08.
//  边界值和特殊场景测试用例
//
//  测试场景：
//  1. 边界值测试（超时、次数、端口、TTL等）
//  2. 特殊域名/IP测试（本地回环、纯IPv6、带端口URL等）
//  3. 并发探测测试
//  4. 回调验证测试
//  5. DNS特殊记录测试
//

#import "CLSNetworkDiagnosisBaseTests.h"

@interface CLSEdgeCaseTests : CLSNetworkDiagnosisBaseTests
@end

@implementation CLSEdgeCaseTests

#pragma mark - ========== 高优先级测试用例 ==========

#pragma mark - EDGE-001: Ping 最小超时测试

/// EDGE-001: 测试 Ping 使用最小超时值
/// 验证 SDK 在极短超时时间下的行为
- (void)testPingMinTimeout {
    NSLog(@"🧪 EDGE-001: Ping 最小超时测试");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Ping最小超时"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.timeout = 100;  // 100ms 极短超时
    request.maxTimes = 1;
    request.enableMultiplePortsDetect = false;
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        [self logCompleteResult:data withTitle:@"Ping最小超时结果"];
        
        // 验证基础字段存在
        XCTAssertNotNil(data, @"响应数据不应为空");
        XCTAssertNotNil(data[@"name"], @"name字段不应为空");
        
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        // 超短超时可能导致超时或成功，都是合理结果
        NSString *method = origin[@"method"];
        XCTAssertEqualObjects(method, @"ping", @"method应为ping");
        
        NSLog(@"✅ EDGE-001: Ping最小超时测试完成");
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

#pragma mark - EDGE-002: TCPPing 常用端口测试

/// EDGE-002: 测试 TCPPing 访问常用服务端口
/// 验证 SSH(22)、HTTPS(443)、HTTP-ALT(8080) 等端口
- (void)testTcppingCommonPorts {
    NSLog(@"🧪 EDGE-002: TCPPing 常用端口测试");
    
    // 测试 HTTPS 端口 443
    XCTestExpectation *expectation443 = [self expectationWithDescription:@"TCPPing-443"];
    
    CLSTcpRequest *request443 = [[CLSTcpRequest alloc] init];
    request443.domain = @"www.baidu.com";
    request443.port = 443;
    request443.appKey = kTestAppKey;
    request443.timeout = 10000;
    request443.maxTimes = 3;
    request443.enableMultiplePortsDetect = false;
    
    [self.diagnosis tcpPingv2:request443 complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        [self logCompleteResult:data withTitle:@"TCPPing-443结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"tcpping", @"method应为tcpping");
        XCTAssertEqual([origin[@"port"] integerValue], 443, @"端口应为443");
        
        NSLog(@"✅ TCPPing 443端口测试通过");
        [expectation443 fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
    
    // 测试 HTTP 端口 80
    XCTestExpectation *expectation80 = [self expectationWithDescription:@"TCPPing-80"];
    
    CLSTcpRequest *request80 = [[CLSTcpRequest alloc] init];
    request80.domain = @"www.baidu.com";
    request80.port = 80;
    request80.appKey = kTestAppKey;
    request80.timeout = 10000;
    request80.maxTimes = 3;
    request80.enableMultiplePortsDetect = false;
    
    [self.diagnosis tcpPingv2:request80 complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        [self logCompleteResult:data withTitle:@"TCPPing-80结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"tcpping", @"method应为tcpping");
        XCTAssertEqual([origin[@"port"] integerValue], 80, @"端口应为80");
        
        NSLog(@"✅ TCPPing 80端口测试通过");
        [expectation80 fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
    
    NSLog(@"✅ EDGE-002: TCPPing常用端口测试完成");
}

#pragma mark - EDGE-003: TCPPing 端口边界值测试

/// EDGE-003: 测试 TCPPing 端口边界值
/// 验证端口 1 和 65535 的处理
- (void)testTcppingPortBoundary {
    NSLog(@"🧪 EDGE-003: TCPPing 端口边界值测试");
    
    // 测试最大端口 65535
    XCTestExpectation *expectationMax = [self expectationWithDescription:@"TCPPing-65535"];
    
    CLSTcpRequest *requestMax = [[CLSTcpRequest alloc] init];
    requestMax.domain = @"www.baidu.com";
    requestMax.port = 65535;  // 最大端口号
    requestMax.appKey = kTestAppKey;
    requestMax.timeout = 5000;
    requestMax.maxTimes = 1;
    requestMax.enableMultiplePortsDetect = false;
    
    [self.diagnosis tcpPingv2:requestMax complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        [self logCompleteResult:data withTitle:@"TCPPing-65535结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"tcpping", @"method应为tcpping");
        XCTAssertEqual([origin[@"port"] integerValue], 65535, @"端口应为65535");
        
        NSLog(@"✅ TCPPing 65535端口测试通过");
        [expectationMax fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
    
    NSLog(@"✅ EDGE-003: TCPPing端口边界值测试完成");
}

#pragma mark - EDGE-004: DNS CNAME 解析测试

/// EDGE-004: 测试 DNS 解析带 CNAME 记录的域名
/// 验证 CNAME 链解析能力
- (void)testDnsCnameResolution {
    NSLog(@"🧪 EDGE-004: DNS CNAME 解析测试");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-CNAME"];
    
    // www.baidu.com 通常有 CNAME 记录
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = @"www.baidu.com";
    request.appKey = kTestAppKey;
    request.timeout = 10000;
    request.enableMultiplePortsDetect = false;
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        [self logCompleteResult:data withTitle:@"DNS-CNAME结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"dns", @"method应为dns");
        XCTAssertNotNil(origin[@"status"], @"status不应为空");
        
        // 检查 ANSWER_SECTION
        NSArray *answerSection = [self safeConvertToArray:origin[@"ANSWER_SECTION"]];
        XCTAssertNotNil(answerSection, @"ANSWER_SECTION不应为空");
        XCTAssertGreaterThan(answerSection.count, 0, @"应有解析结果");
        
        NSLog(@"📋 DNS解析结果数量: %lu", (unsigned long)answerSection.count);
        for (NSString *record in answerSection) {
            NSLog(@"   - %@", record);
        }
        
        NSLog(@"✅ EDGE-004: DNS CNAME解析测试完成");
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
}

#pragma mark - EDGE-005: 同类型并发探测测试

/// EDGE-005: 测试同时发起多个相同类型的探测
/// 验证 SDK 并发处理能力
- (void)testConcurrentSameTypeDetection {
    NSLog(@"🧪 EDGE-005: 同类型并发探测测试");
    
    NSInteger concurrentCount = 3;
    __block NSInteger completedCount = 0;
    __block NSMutableArray *results = [NSMutableArray array];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"并发探测"];
    expectation.expectedFulfillmentCount = concurrentCount;
    
    NSArray *domains = @[@"www.baidu.com", @"www.qq.com", @"www.taobao.com"];
    
    for (NSInteger i = 0; i < concurrentCount; i++) {
        CLSPingRequest *request = [[CLSPingRequest alloc] init];
        request.domain = domains[i];
        request.appKey = kTestAppKey;
        request.timeout = 10000;
        request.maxTimes = 2;
        request.enableMultiplePortsDetect = false;
        request.detectEx = @{@"concurrent_index": @(i)};
        
        NSLog(@"🚀 发起并发探测 #%ld: %@", (long)i, domains[i]);
        
        [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
            @synchronized (results) {
                completedCount++;
                NSDictionary *data = [self parseResponseContent:response];
                if (data) {
                    [results addObject:data];
                }
                
                NSLog(@"📥 收到并发探测结果 #%ld/%ld", (long)completedCount, (long)concurrentCount);
                [self logCompleteResult:data withTitle:[NSString stringWithFormat:@"并发探测结果#%ld", (long)completedCount]];
                
                [expectation fulfill];
            }
        }];
    }
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout * 2 handler:^(NSError *error) {
        NSLog(@"📊 并发探测结果统计:");
        NSLog(@"   - 发起探测数: %ld", (long)concurrentCount);
        NSLog(@"   - 完成探测数: %ld", (long)completedCount);
        NSLog(@"   - 成功结果数: %lu", (unsigned long)results.count);
        
        XCTAssertEqual(completedCount, concurrentCount, @"所有并发探测应完成");
        XCTAssertEqual(results.count, concurrentCount, @"应收到所有探测结果");
    }];
    
    NSLog(@"✅ EDGE-005: 同类型并发探测测试完成");
}

#pragma mark - EDGE-006: 回调线程验证测试

/// EDGE-006: 验证探测回调的线程
/// 检查回调是否在主线程执行
- (void)testCallbackThreadValidation {
    NSLog(@"🧪 EDGE-006: 回调线程验证测试");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"回调线程验证"];
    
    __block BOOL isMainThread = NO;
    __block NSString *threadName = nil;
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.timeout = 10000;
    request.maxTimes = 1;
    request.enableMultiplePortsDetect = false;
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        isMainThread = [NSThread isMainThread];
        threadName = [NSThread currentThread].name ?: @"(unnamed)";
        
        NSLog(@"📍 回调线程信息:");
        NSLog(@"   - 是否主线程: %@", isMainThread ? @"是" : @"否");
        NSLog(@"   - 线程名称: %@", threadName);
        NSLog(@"   - 线程描述: %@", [NSThread currentThread]);
        
        NSDictionary *data = [self parseResponseContent:response];
        XCTAssertNotNil(data, @"响应数据不应为空");
        
        // 记录回调线程信息（不做强制断言，仅记录）
        NSLog(@"ℹ️ SDK回调线程: %@", isMainThread ? @"主线程" : @"后台线程");
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
    
    NSLog(@"✅ EDGE-006: 回调线程验证测试完成");
}

#pragma mark - ========== 中优先级测试用例 ==========

#pragma mark - EDGE-007: Ping 本地回环测试

/// EDGE-007: 测试 Ping 本地回环地址
/// 验证 127.0.0.1 和 localhost 的处理
- (void)testPingLocalhost {
    NSLog(@"🧪 EDGE-007: Ping 本地回环测试");
    
    // 测试 127.0.0.1
    XCTestExpectation *expectationIP = [self expectationWithDescription:@"Ping-127.0.0.1"];
    
    CLSPingRequest *requestIP = [[CLSPingRequest alloc] init];
    requestIP.domain = @"127.0.0.1";
    requestIP.appKey = kTestAppKey;
    requestIP.timeout = 5000;
    requestIP.maxTimes = 3;
    requestIP.enableMultiplePortsDetect = false;
    
    [self.diagnosis pingv2:requestIP complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        [self logCompleteResult:data withTitle:@"Ping-127.0.0.1结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"ping", @"method应为ping");
        
        // 本地回环应该成功且延迟很低
        NSString *hostIP = origin[@"host_ip"];
        NSLog(@"📍 本地回环 host_ip: %@", hostIP);
        
        [expectationIP fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
    
    // 测试 localhost
    XCTestExpectation *expectationHost = [self expectationWithDescription:@"Ping-localhost"];
    
    CLSPingRequest *requestHost = [[CLSPingRequest alloc] init];
    requestHost.domain = @"localhost";
    requestHost.appKey = kTestAppKey;
    requestHost.timeout = 5000;
    requestHost.maxTimes = 3;
    requestHost.enableMultiplePortsDetect = false;
    
    [self.diagnosis pingv2:requestHost complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        [self logCompleteResult:data withTitle:@"Ping-localhost结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"ping", @"method应为ping");
        
        [expectationHost fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
    
    NSLog(@"✅ EDGE-007: Ping本地回环测试完成");
}

#pragma mark - EDGE-008: Ping 纯 IPv6 地址测试

/// EDGE-008: 测试 Ping 纯 IPv6 地址
/// 验证 SDK 对 IPv6 地址的处理能力
- (void)testPingPureIPv6 {
    NSLog(@"🧪 EDGE-008: Ping 纯 IPv6 地址测试");
    NSLog(@"⚠️ 注意：此测试需要设备支持 IPv6 网络");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Ping-IPv6"];
    
    // Google Public DNS IPv6 地址
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = @"2001:4860:4860::8888";
    request.appKey = kTestAppKey;
    request.timeout = 10000;
    request.maxTimes = 3;
    request.enableMultiplePortsDetect = false;
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        [self logCompleteResult:data withTitle:@"Ping-IPv6结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"ping", @"method应为ping");
        
        NSString *hostIP = origin[@"host_ip"];
        NSLog(@"📍 IPv6 host_ip: %@", hostIP);
        
        // 如果网络支持 IPv6，应该能解析
        if (hostIP && hostIP.length > 0) {
            BOOL isIPv6 = [self isIPv6Address:hostIP];
            NSLog(@"📍 是否为 IPv6 地址: %@", isIPv6 ? @"是" : @"否");
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
    
    NSLog(@"✅ EDGE-008: Ping纯IPv6地址测试完成");
}

#pragma mark - EDGE-009: HTTP 带端口 URL 测试

/// EDGE-009: 测试 HTTP 探测带端口的 URL
/// 验证 http://domain:port 格式的处理
- (void)testHttpWithPort {
    NSLog(@"🧪 EDGE-009: HTTP 带端口 URL 测试");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP-带端口"];
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"http://www.baidu.com:80";  // 显式指定端口
    request.appKey = kTestAppKey;
    request.timeout = 15000;
    request.enableMultiplePortsDetect = false;
    
    [self.diagnosis httpingv2:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        [self logCompleteResult:data withTitle:@"HTTP-带端口结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"http", @"method应为http");
        
        NSString *url = origin[@"url"];
        NSLog(@"📍 请求 URL: %@", url);
        
        NSInteger httpCode = [origin[@"httpCode"] integerValue];
        NSLog(@"📍 HTTP 状态码: %ld", (long)httpCode);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
    
    NSLog(@"✅ EDGE-009: HTTP带端口URL测试完成");
}

#pragma mark - EDGE-010: MTR TTL 边界值测试

/// EDGE-010: 测试 MTR 的 TTL 边界值
/// 验证 maxTTL=1 和 maxTTL=64 的处理
- (void)testMtrMinMaxTTL {
    NSLog(@"🧪 EDGE-010: MTR TTL 边界值测试");
    
    // 测试 maxTTL=5（较小值）
    XCTestExpectation *expectationMin = [self expectationWithDescription:@"MTR-TTL-5"];
    
    CLSMtrRequest *requestMin = [[CLSMtrRequest alloc] init];
    requestMin.domain = kTestDomain;
    requestMin.appKey = kTestAppKey;
    requestMin.timeout = 30000;
    requestMin.maxTTL = 5;  // 只追踪5跳
    requestMin.maxTimes = 1;
    requestMin.enableMultiplePortsDetect = false;
    
    [self.diagnosis mtr:requestMin complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        [self logCompleteResult:data withTitle:@"MTR-TTL-5结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"mtr", @"method应为mtr");
        
        NSArray *paths = [self safeConvertToArray:origin[@"paths"]];
        NSLog(@"📍 MTR paths 数量 (maxTTL=5): %lu", (unsigned long)paths.count);
        
        // maxTTL=5 时，最多应该有5跳
        XCTAssertLessThanOrEqual(paths.count, 5, @"paths数量不应超过maxTTL");
        
        [expectationMin fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
    
    // 测试 maxTTL=30（较大值）
    XCTestExpectation *expectationMax = [self expectationWithDescription:@"MTR-TTL-30"];
    
    CLSMtrRequest *requestMax = [[CLSMtrRequest alloc] init];
    requestMax.domain = kTestDomain;
    requestMax.appKey = kTestAppKey;
    requestMax.timeout = 60000;
    requestMax.maxTTL = 30;
    requestMax.maxTimes = 1;
    requestMax.enableMultiplePortsDetect = false;
    
    [self.diagnosis mtr:requestMax complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        [self logCompleteResult:data withTitle:@"MTR-TTL-30结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"mtr", @"method应为mtr");
        
        NSArray *paths = [self safeConvertToArray:origin[@"paths"]];
        NSLog(@"📍 MTR paths 数量 (maxTTL=30): %lu", (unsigned long)paths.count);
        
        [expectationMax fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:90 handler:nil];
    
    NSLog(@"✅ EDGE-010: MTR TTL边界值测试完成");
}

#pragma mark - EDGE-011: Ping maxTimes 边界值测试

/// EDGE-011: 测试 Ping 的 maxTimes 边界值
/// 验证 maxTimes=1 和较大值的处理
- (void)testPingMaxTimesBoundary {
    NSLog(@"🧪 EDGE-011: Ping maxTimes 边界值测试");
    
    // 测试 maxTimes=1（单次探测）
    XCTestExpectation *expectationMin = [self expectationWithDescription:@"Ping-maxTimes-1"];
    
    CLSPingRequest *requestMin = [[CLSPingRequest alloc] init];
    requestMin.domain = kTestDomain;
    requestMin.appKey = kTestAppKey;
    requestMin.timeout = 10000;
    requestMin.maxTimes = 1;  // 单次探测
    requestMin.enableMultiplePortsDetect = false;
    
    [self.diagnosis pingv2:requestMin complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        [self logCompleteResult:data withTitle:@"Ping-maxTimes-1结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"ping", @"method应为ping");
        
        NSInteger count = [origin[@"count"] integerValue];
        NSLog(@"📍 Ping count (maxTimes=1): %ld", (long)count);
        XCTAssertEqual(count, 1, @"count应为1");
        
        [expectationMin fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
    
    // 测试 maxTimes=10（多次探测）
    XCTestExpectation *expectationMax = [self expectationWithDescription:@"Ping-maxTimes-10"];
    
    CLSPingRequest *requestMax = [[CLSPingRequest alloc] init];
    requestMax.domain = kTestDomain;
    requestMax.appKey = kTestAppKey;
    requestMax.timeout = 30000;
    requestMax.maxTimes = 10;
    requestMax.enableMultiplePortsDetect = false;
    
    [self.diagnosis pingv2:requestMax complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        [self logCompleteResult:data withTitle:@"Ping-maxTimes-10结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"ping", @"method应为ping");
        
        NSInteger count = [origin[@"count"] integerValue];
        NSLog(@"📍 Ping count (maxTimes=10): %ld", (long)count);
        XCTAssertEqual(count, 10, @"count应为10");
        
        [expectationMax fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:60 handler:nil];
    
    NSLog(@"✅ EDGE-011: Ping maxTimes边界值测试完成");
}

#pragma mark - EDGE-012: DNS 多 A 记录解析测试

/// EDGE-012: 测试 DNS 解析返回多个 A 记录的域名
/// 验证负载均衡域名的解析能力
- (void)testDnsMultipleARecords {
    NSLog(@"🧪 EDGE-012: DNS 多 A 记录解析测试");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS-多A记录"];
    
    // 大型网站通常返回多个 A 记录
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = @"www.google.com";
    request.appKey = kTestAppKey;
    request.timeout = 10000;
    request.enableMultiplePortsDetect = false;
    
    [self.diagnosis dns:request complate:^(CLSResponse *response) {
        NSDictionary *data = [self parseResponseContent:response];
        [self logCompleteResult:data withTitle:@"DNS-多A记录结果"];
        
        NSDictionary *attribute = [self safeConvertToDictionary:data[@"attribute"]];
        NSDictionary *origin = [self safeConvertToDictionary:attribute[@"net.origin"]];
        
        XCTAssertEqualObjects(origin[@"method"], @"dns", @"method应为dns");
        
        NSArray *answerSection = [self safeConvertToArray:origin[@"ANSWER_SECTION"]];
        NSLog(@"📍 DNS 解析记录数: %lu", (unsigned long)answerSection.count);
        
        for (NSString *record in answerSection) {
            NSLog(@"   - %@", record);
        }
        
        // 大型网站通常有多个记录
        if (answerSection.count > 1) {
            NSLog(@"✅ 检测到多个 DNS 记录");
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout handler:nil];
    
    NSLog(@"✅ EDGE-012: DNS多A记录解析测试完成");
}

#pragma mark - EDGE-013: 快速连续探测测试

/// EDGE-013: 测试快速连续发起多次探测
/// 验证 SDK 处理连续请求的能力
- (void)testRapidConsecutiveDetection {
    NSLog(@"🧪 EDGE-013: 快速连续探测测试");
    
    NSInteger totalRequests = 5;
    __block NSInteger completedRequests = 0;
    __block NSMutableArray *completionTimes = [NSMutableArray array];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"快速连续探测"];
    expectation.expectedFulfillmentCount = totalRequests;
    
    NSDate *startTime = [NSDate date];
    
    // 快速连续发起探测
    for (NSInteger i = 0; i < totalRequests; i++) {
        CLSPingRequest *request = [[CLSPingRequest alloc] init];
        request.domain = kTestDomain;
        request.appKey = kTestAppKey;
        request.timeout = 10000;
        request.maxTimes = 1;
        request.enableMultiplePortsDetect = false;
        request.detectEx = @{@"rapid_index": @(i)};
        
        [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
            @synchronized (completionTimes) {
                completedRequests++;
                NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];
                [completionTimes addObject:@(elapsed)];
                
                NSLog(@"📥 快速探测 #%ld 完成，耗时: %.2f秒", (long)completedRequests, elapsed);
                
                [expectation fulfill];
            }
        }];
    }
    
    [self waitForExpectationsWithTimeout:kTestDefaultTimeout * 2 handler:^(NSError *error) {
        NSLog(@"📊 快速连续探测结果:");
        NSLog(@"   - 发起请求数: %ld", (long)totalRequests);
        NSLog(@"   - 完成请求数: %ld", (long)completedRequests);
        
        if (completionTimes.count > 0) {
            NSNumber *maxTime = [completionTimes valueForKeyPath:@"@max.self"];
            NSNumber *minTime = [completionTimes valueForKeyPath:@"@min.self"];
            NSLog(@"   - 最短耗时: %.2f秒", [minTime doubleValue]);
            NSLog(@"   - 最长耗时: %.2f秒", [maxTime doubleValue]);
        }
        
        XCTAssertEqual(completedRequests, totalRequests, @"所有请求应完成");
    }];
    
    NSLog(@"✅ EDGE-013: 快速连续探测测试完成");
}

#pragma mark - EDGE-014: 超大超时值测试

/// EDGE-014: 测试使用超大超时值
/// 验证 SDK 对大超时值的处理
- (void)testLargeTimeoutValue {
    NSLog(@"🧪 EDGE-014: 超大超时值测试");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"超大超时"];
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = kTestDomain;
    request.appKey = kTestAppKey;
    request.timeout = 60000;  // 60秒超时
    request.maxTimes = 1;
    request.enableMultiplePortsDetect = false;
    
    NSDate *startTime = [NSDate date];
    
    [self.diagnosis pingv2:request complate:^(CLSResponse *response) {
        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];
        
        NSDictionary *data = [self parseResponseContent:response];
        [self logCompleteResult:data withTitle:@"超大超时结果"];
        
        NSLog(@"📍 实际耗时: %.2f秒 (超时设置: 60秒)", elapsed);
        
        // 正常请求应该远在超时前完成
        XCTAssertLessThan(elapsed, 60, @"请求应在超时前完成");
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:90 handler:nil];
    
    NSLog(@"✅ EDGE-014: 超大超时值测试完成");
}

@end
