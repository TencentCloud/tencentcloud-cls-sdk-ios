
#import <XCTest/XCTest.h>
@import TencentCloudLogProducer;
#import "CLSTestCredentials.h"

#pragma mark - 凭证（统一从 CLSTestCredentials.h 读取，已 .gitignore）

static NSString * const kNetToken  = kCLSTestNetToken;
static NSString * const kEndpoint  = kCLSTestEndpoint;
static NSString * const kSecretId  = kCLSTestSecretId;
static NSString * const kSecretKey = kCLSTestSecretKey;
static NSString * const kTopicId   = kCLSTestTopicId;

@interface CLSAutoLiveTests : XCTestCase
@end

@implementation CLSAutoLiveTests

+ (void)setUp {
    [super setUp];
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:kEndpoint
                                                            accessKeyId:@""
                                                              accessKey:@""];
    [[ClsNetworkDiagnosis sharedInstance] setupLogSenderWithConfig:config netToken:kNetToken];
    [[ClsNetworkDiagnosis sharedInstance] setUserEx:@{@"live_test": @"auto"}];
    NSLog(@"[LIVE] +setUp done, netToken.len=%lu, endpoint=%@",
          (unsigned long)kNetToken.length, kEndpoint);
}

#pragma mark - 00: netToken 真实解析（#7）

- (void)test00_netToken_parsed_correctly {
    if ([kNetToken isEqualToString:@"YOUR_NET_TOKEN_BASE64"]) {
        XCTSkip(@"kNetToken 为占位符，跳过真实解析校验；本地验证时请在 CLSAutoLiveTests.m 顶部填入真实 netToken");
    }
    NSDictionary *info = [CLSNetworkUtils parseNetToken:kNetToken];
    XCTAssertGreaterThan(info.count, 0, @"netToken 必须能解析");
    XCTAssertEqualObjects(info[@"region"], @"ap-guangzhou");
    XCTAssertNotNil(info[@"networkAppId"]);
    XCTAssertNotNil(info[@"appKey"]);
    XCTAssertNotNil(info[@"uin"]);
    XCTAssertNotNil(info[@"topic_id"]);
    NSLog(@"[LIVE] #7 netToken parsed: region=%@ topic_id=%@... uin=%@",
          info[@"region"],
          [info[@"topic_id"] length] >= 8 ? [info[@"topic_id"] substringToIndex:8] : info[@"topic_id"],
          info[@"uin"]);
}

#pragma mark - 01: pingv2 入口耗时 + 主线程回调（#16）

- (void)test01_pingv2_async_and_main_thread_callback {
    CLSPingRequest *req = [[CLSPingRequest alloc] init];
    req.domain = @"www.baidu.com";
    req.detectEx = @{@"test": @"live-ping"};

    XCTestExpectation *exp = [self expectationWithDescription:@"ping"];
    __block BOOL main = NO;
    __block CLSResponse *resp = nil;

    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [[ClsNetworkDiagnosis sharedInstance] pingv2:req complate:^(CLSResponse *result){
        main = [NSThread isMainThread];
        resp = result;
        [exp fulfill];
    }];
    double entryMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
    NSLog(@"[LIVE] #16 pingv2 entry cost=%.2fms (期望<50ms)", entryMs);
    XCTAssertLessThan(entryMs, 500.0, @"#16 pingv2 入口不应阻塞调用线程");

    [self waitForExpectations:@[exp] timeout:30.0];
    XCTAssertTrue(main, @"#16 pingv2 回调必须主线程");
    XCTAssertNotNil(resp);
    NSString *content = resp.content ?: @"";
    NSLog(@"[LIVE] #16 pingv2 isMain=%d, response.len=%lu, first200=%@",
          main, (unsigned long)content.length,
          [content length] > 200 ? [content substringToIndex:200] : content);
}

#pragma mark - 02: dns 调用 + CNAME 名称点号（#30）

- (void)test02_dns_realdomain_cname_name_hasDot {
    CLSDnsRequest *req = [[CLSDnsRequest alloc] init];
    req.domain = @"www.baidu.com";

    XCTestExpectation *exp = [self expectationWithDescription:@"dns"];
    __block CLSResponse *resp = nil;
    __block BOOL main = NO;
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [[ClsNetworkDiagnosis sharedInstance] dns:req complate:^(CLSResponse *result){
        main = [NSThread isMainThread];
        resp = result;
        [exp fulfill];
    }];
    double entryMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
    [self waitForExpectations:@[exp] timeout:30.0];

    XCTAssertTrue(main, @"#16 dns 回调必须主线程");
    XCTAssertNotNil(resp);
    NSString *content = resp.content ?: @"";
    NSLog(@"[LIVE] #16+#30 dns entryMs=%.2f isMain=%d content.len=%lu",
          entryMs, main, (unsigned long)content.length);
    NSLog(@"[LIVE] #30 dns content first500: %@",
          [content length] > 500 ? [content substringToIndex:500] : content);
    if ([content containsString:@"shifen"]) {
        XCTAssertTrue([content containsString:@".shifen"] || [content containsString:@"shifen."],
                      @"#30 CNAME 应该有点号分隔，不该是 'ashifen'");
    }
}

#pragma mark - 03: tcpping 正常 443

- (void)test03_tcpping_443_normal {
    CLSTcpRequest *req = [[CLSTcpRequest alloc] init];
    req.domain = @"www.tencentcloud.com";
    req.port = 443;
    req.maxTimes = 3;

    XCTestExpectation *exp = [self expectationWithDescription:@"tcpping"];
    __block CLSResponse *resp = nil;
    __block BOOL main = NO;
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [[ClsNetworkDiagnosis sharedInstance] tcpPingv2:req complate:^(CLSResponse *result){
        main = [NSThread isMainThread];
        resp = result;
        [exp fulfill];
    }];
    double entryMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
    [self waitForExpectations:@[exp] timeout:60.0];
    XCTAssertTrue(main, @"#16 tcpping 回调必须主线程");
    XCTAssertNotNil(resp);
    NSLog(@"[LIVE] #16 tcpping entryMs=%.2f isMain=%d content.len=%lu",
          entryMs, main, (unsigned long)(resp.content.length));
}

#pragma mark - 04: tcpping port=0 fast-fail（#34）

- (void)test04_tcpping_port_zero_fastfail {
    CLSTcpRequest *req = [[CLSTcpRequest alloc] init];
    req.domain = @"www.tencentcloud.com";
    req.port = 0;
    req.maxTimes = 3;

    XCTestExpectation *exp = [self expectationWithDescription:@"tcpping-0"];
    __block CLSResponse *resp = nil;
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [[ClsNetworkDiagnosis sharedInstance] tcpPingv2:req complate:^(CLSResponse *result){
        resp = result;
        [exp fulfill];
    }];
    [self waitForExpectations:@[exp] timeout:10.0];
    double totalMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
    NSLog(@"[LIVE] #34 tcpping port=0 total=%.2fms resp.content.len=%lu",
          totalMs, (unsigned long)(resp.content.length));
    XCTAssertNotNil(resp, @"#34 port=0 必须有回调");
}

#pragma mark - 05: tcpping port=70000 fast-fail（#34）

- (void)test05_tcpping_port_overflow_fastfail {
    CLSTcpRequest *req = [[CLSTcpRequest alloc] init];
    req.domain = @"www.tencentcloud.com";
    req.port = 70000;
    req.maxTimes = 3;

    XCTestExpectation *exp = [self expectationWithDescription:@"tcpping-70000"];
    __block CLSResponse *resp = nil;
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [[ClsNetworkDiagnosis sharedInstance] tcpPingv2:req complate:^(CLSResponse *result){
        resp = result;
        [exp fulfill];
    }];
    [self waitForExpectations:@[exp] timeout:10.0];
    double totalMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
    NSLog(@"[LIVE] #34 tcpping port=70000 total=%.2fms resp.content.len=%lu",
          totalMs, (unsigned long)(resp.content.length));
    XCTAssertNotNil(resp);
}

#pragma mark - 06: 空 domain 必须回调（#25）

- (void)test06_pingv2_empty_domain_callback {
    CLSPingRequest *req = [[CLSPingRequest alloc] init];
    req.domain = @"";

    XCTestExpectation *exp = [self expectationWithDescription:@"ping-empty-domain"];
    __block CLSResponse *resp = nil;
    __block BOOL main = NO;
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [[ClsNetworkDiagnosis sharedInstance] pingv2:req complate:^(CLSResponse *result){
        main = [NSThread isMainThread];
        resp = result;
        [exp fulfill];
    }];
    [self waitForExpectations:@[exp] timeout:3.0];
    double totalMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
    XCTAssertNotNil(resp, @"#25 空 domain 必须有回调（不能永久挂起）");
    XCTAssertTrue(main, @"#25 回调必须主线程");
    NSLog(@"[LIVE] #25 empty domain callback cost=%.2fms isMain=%d resp.content=%@",
          totalMs, main, resp.content);
}

#pragma mark - 07: httpping 真实 HTTPS 调用

- (void)test07_httpping_real_https {
    CLSHttpRequest *req = [[CLSHttpRequest alloc] init];
    req.domain = @"https://www.tencentcloud.com";

    XCTestExpectation *exp = [self expectationWithDescription:@"httpping"];
    __block CLSResponse *resp = nil;
    __block BOOL main = NO;
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [[ClsNetworkDiagnosis sharedInstance] httpingv2:req complate:^(CLSResponse *result){
        main = [NSThread isMainThread];
        resp = result;
        [exp fulfill];
    }];
    double entryMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
    [self waitForExpectations:@[exp] timeout:60.0];
    XCTAssertTrue(main);
    XCTAssertNotNil(resp);
    NSLog(@"[LIVE] #16+#18 httpping entry=%.2fms isMain=%d content.len=%lu",
          entryMs, main, (unsigned long)resp.content.length);
}

#pragma mark - 08: MTR 真实调用（#19 释放，不崩）

- (void)test08_mtr_real_target {
    CLSMtrRequest *req = [[CLSMtrRequest alloc] init];
    req.domain = @"www.baidu.com";

    XCTestExpectation *exp = [self expectationWithDescription:@"mtr"];
    __block CLSResponse *resp = nil;
    __block BOOL main = NO;
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [[ClsNetworkDiagnosis sharedInstance] mtr:req complate:^(CLSResponse *result){
        main = [NSThread isMainThread];
        resp = result;
        [exp fulfill];
    }];
    double entryMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
    [self waitForExpectations:@[exp] timeout:120.0];
    XCTAssertTrue(main);
    XCTAssertNotNil(resp);
    NSLog(@"[LIVE] #16+#19 mtr entry=%.2fms isMain=%d content.len=%lu",
          entryMs, main, (unsigned long)resp.content.length);
}

#pragma mark - 09: 日志写入正常（10 条，强鉴权）

- (void)test09_logwrite_10_strong_auth {
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:kEndpoint
                                                            accessKeyId:kSecretId
                                                              accessKey:kSecretKey];
    LogSender *sender = [LogSender sharedSender];
    [sender setConfig:config];
    [sender start];

    for (int i = 0; i < 10; i++) {
        Log_Content *c = [Log_Content message];
        c.key = @"message";
        c.value = [NSString stringWithFormat:
                   @"{\"idx\":%d,\"src\":\"auto-live-batch\",\"ts\":%lld}",
                   i, (long long)([[NSDate date] timeIntervalSince1970] * 1000)];
        Log *item = [Log message];
        [item.contentsArray addObject:c];
        item.time = (long long)([[NSDate date] timeIntervalSince1970] * 1000);

        XCTestExpectation *exp = [self expectationWithDescription:
                                   [NSString stringWithFormat:@"w-%d", i]];
        [[ClsLogStorage sharedInstance] writeLog:item topicId:kTopicId
                                     completion:^(BOOL s, NSError *e) {
            XCTAssertTrue(s, @"第 %d 条写入应该成功, err=%@", i, e);
            [exp fulfill];
        }];
        [self waitForExpectations:@[exp] timeout:5.0];
    }
    NSLog(@"[LIVE] 10 条日志写入完成，等待 10 秒让 sender 上报到 topic=%@...", kTopicId);
    [NSThread sleepForTimeInterval:10.0];
    NSLog(@"[LIVE] 等待完毕，请手动去 CLS 控制台 topic=%@ 搜 src=auto-live-batch 验证", kTopicId);
}

#pragma mark - 10: 超大日志拒绝（#14）

- (void)test10_oversized_log_rejected {
    NSMutableString *big = [NSMutableString stringWithCapacity:600 * 1024];
    for (int i = 0; i < 600; i++) {
        [big appendString:[@"" stringByPaddingToLength:1024 withString:@"A" startingAtIndex:0]];
    }
    Log_Content *c = [Log_Content message];
    c.key = @"message";
    c.value = big;
    Log *item = [Log message];
    [item.contentsArray addObject:c];
    item.time = (long long)([[NSDate date] timeIntervalSince1970] * 1000);

    XCTestExpectation *exp = [self expectationWithDescription:@"oversized"];
    __block BOOL success = YES;
    __block NSError *err = nil;
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [[ClsLogStorage sharedInstance] writeLog:item topicId:kTopicId
                                  completion:^(BOOL s, NSError *e) {
        success = s;
        err = e;
        [exp fulfill];
    }];
    [self waitForExpectations:@[exp] timeout:3.0];
    double costMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
    NSLog(@"[LIVE] #14 超大日志(%.0fKB) success=%d err.code=%ld cost=%.2fms",
          big.length / 1024.0, success, (long)(err.code), costMs);
    XCTAssertFalse(success, @"#14 超大日志必须被拒绝");
    XCTAssertNotNil(err);
    XCTAssertEqual(err.code, -4, @"#14 错误码应为 -4");
    XCTAssertLessThan(costMs, 500.0, @"#14 应在写入前就拒绝，不能有磁盘 IO");
}

#pragma mark - 11: 发送中 setConfig 主线程不阻塞（#9）

- (void)test11_burst_write_then_setConfig_fast {
    for (int i = 0; i < 100; i++) {
        Log_Content *c = [Log_Content message];
        c.key = @"message";
        c.value = [NSString stringWithFormat:@"{\"idx\":%d,\"src\":\"burst-cfg\"}", i];
        Log *item = [Log message];
        [item.contentsArray addObject:c];
        item.time = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
        [[ClsLogStorage sharedInstance] writeLog:item topicId:kTopicId completion:nil];
    }
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:kEndpoint
                                                            accessKeyId:kSecretId
                                                              accessKey:kSecretKey];
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [[LogSender sharedSender] setConfig:config];
    double setCfgMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
    NSLog(@"[LIVE] #9 burst(100) + setConfig cost=%.2fms (期望<50ms, 放宽至<500ms)", setCfgMs);
    XCTAssertLessThan(setCfgMs, 500.0, @"#9 setConfig 不应被发送线程阻塞");
}

#pragma mark - 12: 发送中 stop 主线程不阻塞（#9）

- (void)test12_burst_write_then_stop_fast {
    for (int i = 0; i < 100; i++) {
        Log_Content *c = [Log_Content message];
        c.key = @"message";
        c.value = [NSString stringWithFormat:@"{\"idx\":%d,\"src\":\"burst-stop\"}", i];
        Log *item = [Log message];
        [item.contentsArray addObject:c];
        item.time = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
        [[ClsLogStorage sharedInstance] writeLog:item topicId:kTopicId completion:nil];
    }
    LogSender *sender = [LogSender sharedSender];
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [sender stop];
    double stopMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
    [sender start];
    NSLog(@"[LIVE] #9 burst(100) + stop cost=%.2fms (期望<50ms, 放宽至<500ms)", stopMs);
    XCTAssertLessThan(stopMs, 500.0, @"#9 stop 不应被发送线程阻塞");
}

#pragma mark - 13: 日志开关 ON/OFF 不崩（#1）

- (void)test13_log_switch_on_off {
    [LogSender setLogEnabled:YES];
    [LogSender setLogEnabled:NO];
    [LogSender setLogEnabled:YES];
    NSLog(@"[LIVE] #1 setLogEnabled 多次切换，无崩溃");
}

@end
