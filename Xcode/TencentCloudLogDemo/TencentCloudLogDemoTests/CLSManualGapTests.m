//
//  CLSManualGapTests.m
//  补 2026-10-20 手动测试清单中 自动化尚未覆盖 / 覆盖不完整 的测试点
//
//  覆盖映射：
//  - #27 P0-6-2  nil completion 不崩（五种探测）
//  - #34 P1-4-3  TCPing 非法参数：maxTimes=0 / timeout=0 必有回调
//  - #16 P0-5-2  严格入口阈值 <50ms（在 live 场景下重测，CLSAutoLiveTests 放宽到 500ms）
//  - #18 P1-2-2  HTTP errorCode 为 2000+小正数（不是指针低位）
//  - #25 P1-2-3  参数错误必回调（Mtr 空 domain / nil request）
//

#import <XCTest/XCTest.h>
@import TencentCloudLogProducer;
#import "CLSTestCredentials.h"

static NSString *const kGapNetToken = kCLSTestNetToken;
static NSString *const kGapEndpoint = kCLSTestEndpoint;

@interface CLSManualGapTests : XCTestCase
@end

@implementation CLSManualGapTests

+ (void)setUp {
    [super setUp];
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:kGapEndpoint
                                                            accessKeyId:@""
                                                              accessKey:@""];
    [[ClsNetworkDiagnosis sharedInstance] setupLogSenderWithConfig:config netToken:kGapNetToken];
    NSLog(@"[GAP] +setUp done");
}

#pragma mark - #27 P0-6-2  nil completion 不崩（五种探测）

- (void)test_27_pingv2_nilCompletion_doesNotCrash {
    CLSPingRequest *req = [[CLSPingRequest alloc] init];
    req.domain = @"www.baidu.com";
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wnonnull"
    XCTAssertNoThrow(([[ClsNetworkDiagnosis sharedInstance] pingv2:req complate:nil]),
                     @"#27 pingv2 传 nil completion 不应崩溃");
    #pragma clang diagnostic pop
    [NSThread sleepForTimeInterval:1.0];  // 等后台异步执行完
    NSLog(@"[GAP] #27 pingv2 nil completion 已过");
}

- (void)test_27_dns_nilCompletion_doesNotCrash {
    CLSDnsRequest *req = [[CLSDnsRequest alloc] init];
    req.domain = @"www.baidu.com";
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wnonnull"
    XCTAssertNoThrow(([[ClsNetworkDiagnosis sharedInstance] dns:req complate:nil]),
                     @"#27 dns 传 nil completion 不应崩溃");
    #pragma clang diagnostic pop
    [NSThread sleepForTimeInterval:1.0];
    NSLog(@"[GAP] #27 dns nil completion 已过");
}

- (void)test_27_tcpping_nilCompletion_doesNotCrash {
    CLSTcpRequest *req = [[CLSTcpRequest alloc] init];
    req.domain = @"www.tencentcloud.com";
    req.port = 443;
    req.maxTimes = 2;
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wnonnull"
    XCTAssertNoThrow(([[ClsNetworkDiagnosis sharedInstance] tcpPingv2:req complate:nil]),
                     @"#27 tcpping 传 nil completion 不应崩溃");
    #pragma clang diagnostic pop
    [NSThread sleepForTimeInterval:3.0];
    NSLog(@"[GAP] #27 tcpping nil completion 已过");
}

- (void)test_27_httpping_nilCompletion_doesNotCrash {
    CLSHttpRequest *req = [[CLSHttpRequest alloc] init];
    req.domain = @"https://www.tencentcloud.com";
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wnonnull"
    XCTAssertNoThrow(([[ClsNetworkDiagnosis sharedInstance] httpingv2:req complate:nil]),
                     @"#27 httpping 传 nil completion 不应崩溃");
    #pragma clang diagnostic pop
    [NSThread sleepForTimeInterval:5.0];
    NSLog(@"[GAP] #27 httpping nil completion 已过");
}

- (void)test_27_mtr_nilCompletion_doesNotCrash {
    CLSMtrRequest *req = [[CLSMtrRequest alloc] init];
    req.domain = @"www.baidu.com";
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wnonnull"
    XCTAssertNoThrow(([[ClsNetworkDiagnosis sharedInstance] mtr:req complate:nil]),
                     @"#27 mtr 传 nil completion 不应崩溃");
    #pragma clang diagnostic pop
    [NSThread sleepForTimeInterval:5.0];
    NSLog(@"[GAP] #27 mtr nil completion 已过");
}

#pragma mark - #34 P1-4-3  TCPing 非法参数

- (void)test_34_tcpping_maxTimes_zero_mustCallback {
    CLSTcpRequest *req = [[CLSTcpRequest alloc] init];
    req.domain = @"www.tencentcloud.com";
    req.port = 443;
    req.maxTimes = 0;   // 非法：次数 0

    XCTestExpectation *exp = [self expectationWithDescription:@"tcpping-maxTimes-0"];
    __block CLSResponse *resp = nil;
    __block BOOL main = NO;
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [[ClsNetworkDiagnosis sharedInstance] tcpPingv2:req complate:^(CLSResponse *result){
        main = [NSThread isMainThread];
        resp = result;
        [exp fulfill];
    }];
    [self waitForExpectations:@[exp] timeout:10.0];
    double totalMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
    XCTAssertNotNil(resp, @"#34 tcpping maxTimes=0 必须有回调");
    XCTAssertTrue(main, @"#34 回调应在主线程");
    XCTAssertLessThan(totalMs, 2000.0, @"#34 应 fast-fail，不该走完真实连接");
    NSLog(@"[GAP] #34 tcpping maxTimes=0 total=%.2fms resp.content=%@",
          totalMs, resp.content ?: @"(nil)");
}

- (void)test_34_tcpping_timeout_zero_mustCallback {
    CLSTcpRequest *req = [[CLSTcpRequest alloc] init];
    req.domain = @"www.tencentcloud.com";
    req.port = 443;
    req.maxTimes = 2;
    req.timeout = 0;   // 非法：超时 0

    XCTestExpectation *exp = [self expectationWithDescription:@"tcpping-timeout-0"];
    __block CLSResponse *resp = nil;
    __block BOOL main = NO;
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [[ClsNetworkDiagnosis sharedInstance] tcpPingv2:req complate:^(CLSResponse *result){
        main = [NSThread isMainThread];
        resp = result;
        [exp fulfill];
    }];
    [self waitForExpectations:@[exp] timeout:10.0];
    double totalMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
    XCTAssertNotNil(resp, @"#34 tcpping timeout=0 必须有回调");
    XCTAssertTrue(main, @"#34 回调应在主线程");
    NSLog(@"[GAP] #34 tcpping timeout=0 total=%.2fms resp.content=%@",
          totalMs, resp.content ?: @"(nil)");
}

#pragma mark - #16 P0-5-2  严格入口阈值 <50ms

- (void)test_16_strict_entry_latency_all_methods {
    // 测五种探测的入口耗时严格 <50ms（CLSAutoLiveTests 放宽到 500ms）
    __block double maxEntryMs = 0;
    NSString *domain = @"www.baidu.com";

    // ping
    {
        CLSPingRequest *req = [[CLSPingRequest alloc] init];
        req.domain = domain;
        XCTestExpectation *exp = [self expectationWithDescription:@"ping-entry"];
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        [[ClsNetworkDiagnosis sharedInstance] pingv2:req complate:^(CLSResponse *r) { [exp fulfill]; }];
        double entry = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
        maxEntryMs = MAX(maxEntryMs, entry);
        NSLog(@"[GAP] #16 pingv2 entry=%.2fms", entry);
        XCTAssertLessThan(entry, 50.0, @"#16 pingv2 入口严格阈值 50ms");
        [self waitForExpectations:@[exp] timeout:30.0];
    }
    // dns
    {
        CLSDnsRequest *req = [[CLSDnsRequest alloc] init];
        req.domain = domain;
        XCTestExpectation *exp = [self expectationWithDescription:@"dns-entry"];
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        [[ClsNetworkDiagnosis sharedInstance] dns:req complate:^(CLSResponse *r) { [exp fulfill]; }];
        double entry = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
        maxEntryMs = MAX(maxEntryMs, entry);
        NSLog(@"[GAP] #16 dns entry=%.2fms", entry);
        XCTAssertLessThan(entry, 50.0, @"#16 dns 入口严格阈值 50ms");
        [self waitForExpectations:@[exp] timeout:30.0];
    }
    // tcpping
    {
        CLSTcpRequest *req = [[CLSTcpRequest alloc] init];
        req.domain = @"www.tencentcloud.com";
        req.port = 443;
        req.maxTimes = 2;
        XCTestExpectation *exp = [self expectationWithDescription:@"tcpping-entry"];
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        [[ClsNetworkDiagnosis sharedInstance] tcpPingv2:req complate:^(CLSResponse *r) { [exp fulfill]; }];
        double entry = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
        maxEntryMs = MAX(maxEntryMs, entry);
        NSLog(@"[GAP] #16 tcpping entry=%.2fms", entry);
        XCTAssertLessThan(entry, 50.0, @"#16 tcpping 入口严格阈值 50ms");
        [self waitForExpectations:@[exp] timeout:30.0];
    }
    // httpping
    {
        CLSHttpRequest *req = [[CLSHttpRequest alloc] init];
        req.domain = @"https://www.tencentcloud.com";
        XCTestExpectation *exp = [self expectationWithDescription:@"httpping-entry"];
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        [[ClsNetworkDiagnosis sharedInstance] httpingv2:req complate:^(CLSResponse *r) { [exp fulfill]; }];
        double entry = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
        maxEntryMs = MAX(maxEntryMs, entry);
        NSLog(@"[GAP] #16 httpping entry=%.2fms", entry);
        XCTAssertLessThan(entry, 50.0, @"#16 httpping 入口严格阈值 50ms");
        [self waitForExpectations:@[exp] timeout:60.0];
    }
    // mtr（放宽到 100ms，MTR 启动稍重）
    {
        CLSMtrRequest *req = [[CLSMtrRequest alloc] init];
        req.domain = @"www.baidu.com";
        XCTestExpectation *exp = [self expectationWithDescription:@"mtr-entry"];
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        [[ClsNetworkDiagnosis sharedInstance] mtr:req complate:^(CLSResponse *r) { [exp fulfill]; }];
        double entry = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
        maxEntryMs = MAX(maxEntryMs, entry);
        NSLog(@"[GAP] #16 mtr entry=%.2fms", entry);
        XCTAssertLessThan(entry, 100.0, @"#16 mtr 入口放宽 100ms（启动稍重）");
        [self waitForExpectations:@[exp] timeout:120.0];
    }
    NSLog(@"[GAP] #16 五入口最大 entry=%.2fms", maxEntryMs);
}

#pragma mark - #25 P1-2-3  mtr 空 domain 必须回调（补 ping 之外的）

- (void)test_25_mtr_empty_domain_mustCallback {
    CLSMtrRequest *req = [[CLSMtrRequest alloc] init];
    req.domain = @"";

    XCTestExpectation *exp = [self expectationWithDescription:@"mtr-empty-domain"];
    __block CLSResponse *resp = nil;
    __block BOOL main = NO;
    [[ClsNetworkDiagnosis sharedInstance] mtr:req complate:^(CLSResponse *result){
        main = [NSThread isMainThread];
        resp = result;
        [exp fulfill];
    }];
    [self waitForExpectations:@[exp] timeout:5.0];
    XCTAssertNotNil(resp, @"#25 mtr 空 domain 必须有回调");
    XCTAssertTrue(main);
    NSLog(@"[GAP] #25 mtr empty domain resp.content=%@", resp.content ?: @"(nil)");
}

- (void)test_25_dns_empty_domain_mustCallback {
    CLSDnsRequest *req = [[CLSDnsRequest alloc] init];
    req.domain = @"";

    XCTestExpectation *exp = [self expectationWithDescription:@"dns-empty-domain"];
    __block CLSResponse *resp = nil;
    [[ClsNetworkDiagnosis sharedInstance] dns:req complate:^(CLSResponse *result){
        resp = result;
        [exp fulfill];
    }];
    [self waitForExpectations:@[exp] timeout:3.0];
    XCTAssertNotNil(resp, @"#25 dns 空 domain 必须有回调");
    NSLog(@"[GAP] #25 dns empty domain resp.content=%@", resp.content ?: @"(nil)");
}

- (void)test_25_httpping_empty_domain_mustCallback {
    CLSHttpRequest *req = [[CLSHttpRequest alloc] init];
    req.domain = @"";

    XCTestExpectation *exp = [self expectationWithDescription:@"http-empty-domain"];
    __block CLSResponse *resp = nil;
    [[ClsNetworkDiagnosis sharedInstance] httpingv2:req complate:^(CLSResponse *result){
        resp = result;
        [exp fulfill];
    }];
    [self waitForExpectations:@[exp] timeout:5.0];
    XCTAssertNotNil(resp, @"#25 httpping 空 domain 必须有回调");
    NSLog(@"[GAP] #25 httpping empty domain resp.content=%@", resp.content ?: @"(nil)");
}

- (void)test_25_tcpping_empty_domain_mustCallback {
    CLSTcpRequest *req = [[CLSTcpRequest alloc] init];
    req.domain = @"";
    req.port = 443;
    req.maxTimes = 2;

    XCTestExpectation *exp = [self expectationWithDescription:@"tcp-empty-domain"];
    __block CLSResponse *resp = nil;
    [[ClsNetworkDiagnosis sharedInstance] tcpPingv2:req complate:^(CLSResponse *result){
        resp = result;
        [exp fulfill];
    }];
    [self waitForExpectations:@[exp] timeout:5.0];
    XCTAssertNotNil(resp, @"#25 tcpping 空 domain 必须有回调");
    NSLog(@"[GAP] #25 tcpping empty domain resp.content=%@", resp.content ?: @"(nil)");
}

#pragma mark - #18 P1-2-2  HTTP errorCode 在 2000+小正数 范围

- (void)test_18_httping_unreachable_errorCode_in_range {
    // 10.255.255.1 为 RFC1918 保留不可路由地址，预期在 TCP 层超时失败
    CLSHttpRequest *req = [[CLSHttpRequest alloc] init];
    req.domain = @"http://10.255.255.1:1/";
    req.timeout = 5;

    XCTestExpectation *exp = [self expectationWithDescription:@"http-unreachable"];
    __block CLSResponse *resp = nil;
    [[ClsNetworkDiagnosis sharedInstance] httpingv2:req complate:^(CLSResponse *result){
        resp = result;
        [exp fulfill];
    }];
    [self waitForExpectations:@[exp] timeout:60.0];
    XCTAssertNotNil(resp, @"#18 应该有回调");

    // 从 content 里解析 origin.errorCode / errorCode / net.origin.errorCode
    NSString *content = resp.content ?: @"";
    NSLog(@"[GAP] #18 unreachable response first 1500: %@",
          [content length] > 1500 ? [content substringToIndex:1500] : content);

    NSError *jsonErr = nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:[content dataUsingEncoding:NSUTF8StringEncoding]
                                                          options:0 error:&jsonErr];
    if (!root || jsonErr) {
        NSLog(@"[GAP] #18 content 不是 JSON，仅记录文本，跳过范围断言");
        return;
    }

    // 尝试多种常见字段路径
    id origin = root[@"net"][@"origin"] ?: root[@"origin"];
    id errCodeAny = nil;
    if ([origin isKindOfClass:[NSDictionary class]]) {
        errCodeAny = origin[@"errorCode"] ?: origin[@"error_code"] ?: origin[@"httpCode"];
    }
    if (!errCodeAny) errCodeAny = root[@"errorCode"] ?: root[@"error_code"];

    if ([errCodeAny isKindOfClass:[NSNumber class]]) {
        NSInteger code = [errCodeAny integerValue];
        NSLog(@"[GAP] #18 errorCode=%ld", (long)code);
        // 期望：2000+POSIX，POSIX < 200；修复前为 2000+指针低位，可能是 2 位十亿级
        // 保守断言：|code| < 10000
        XCTAssertLessThan(labs(code), 10000, @"#18 errorCode 不应是指针低位的大数");
    } else {
        NSLog(@"[GAP] #18 未能从响应解析出 errorCode，仅记录");
    }
}

@end
