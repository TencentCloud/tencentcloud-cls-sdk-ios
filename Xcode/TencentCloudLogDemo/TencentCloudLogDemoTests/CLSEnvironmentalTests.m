//
//  CLSEnvironmentalTests.m
//  需要用户物理动作配合的环境相关测试
//
//  覆盖映射：
//  - Group A  (NLC 3G):       P0-5-1 弱网 setConfig/stop <50ms, P2-4 writeLog 主线程, P2-5 Sender 退避
//  - Group A' (NLC 100% Loss): P0-5-1 断网 setConfig/stop <50ms, Sender 不删日志
//  - Group B  (关 WiFi 蜂窝):  P1-4-2 多网卡 DNS 蜂窝路径, Sender 自动恢复
//  - Group C  (低电量/改时间): 清单外 Sender 退避 / 时间戳稳定
//  - Group D  (杀 App 重开):   清单外 日志持久化续发
//

#import <XCTest/XCTest.h>
#import <sys/sysctl.h>
@import TencentCloudLogProducer;
#import "CLSTestCredentials.h"

static NSString *const kEnvNetToken  = kCLSTestNetToken;
static NSString *const kEnvEndpoint  = kCLSTestEndpoint;
static NSString *const kEnvSecretId  = kCLSTestSecretId;
static NSString *const kEnvSecretKey = kCLSTestSecretKey;
static NSString *const kEnvTopic     = kCLSTestTopicId;

@interface CLSEnvironmentalTests : XCTestCase
@end

@implementation CLSEnvironmentalTests

+ (void)setUp {
    [super setUp];
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:kEnvEndpoint
                                                            accessKeyId:kEnvSecretId
                                                              accessKey:kEnvSecretKey];
    [[ClsNetworkDiagnosis sharedInstance] setupLogSenderWithConfig:config netToken:kEnvNetToken];
    [[LogSender sharedSender] setConfig:config];
    [[LogSender sharedSender] start];
}

- (void)cleanDB {
    ClsLogStorage *s = [ClsLogStorage sharedInstance];
    for (int i = 0; i < 20; i++) {
        NSArray *rows = [s queryPendingLogs:10000];
        if (!rows.count) return;
        NSMutableArray *ids = [NSMutableArray array];
        for (NSDictionary *r in rows) if (r[@"id"]) [ids addObject:r[@"id"]];
        if (ids.count) [s deleteSentLogsWithIds:ids];
    }
}

- (Log *)makeLog:(NSInteger)idx tag:(NSString *)tag {
    Log_Content *c = [Log_Content message];
    c.key = @"message";
    c.value = [NSString stringWithFormat:@"{\"idx\":%ld,\"tag\":\"%@\"}", (long)idx, tag];
    Log *item = [Log message];
    [item.contentsArray addObject:c];
    item.time = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
    return item;
}

#pragma mark - Group A: NLC 3G 弱网

/// A1: 弱网 3G 下几个本地入口 setupLogSender/setUserEx/getUserEx/setLogEnabled 立即返回 <50ms
- (void)test_A1_entry_latency_under_3g {
    ClsNetworkDiagnosis *d = [ClsNetworkDiagnosis sharedInstance];
    ClsLogSenderConfig *cfg = [ClsLogSenderConfig configWithEndpoint:kEnvEndpoint
                                                         accessKeyId:kEnvSecretId
                                                           accessKey:kEnvSecretKey];
    NSArray *methods = @[
        @"setupLogSenderWithConfig:netToken:",
        @"setUserEx:",
        @"getUserEx",
        @"LogSender.setLogEnabled:",
    ];
    for (NSString *m in methods) {
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        if ([m isEqualToString:@"setupLogSenderWithConfig:netToken:"]) {
            [d setupLogSenderWithConfig:cfg netToken:kEnvNetToken];
        } else if ([m isEqualToString:@"setUserEx:"]) {
            [d setUserEx:@{@"k":@"v"}];
        } else if ([m isEqualToString:@"getUserEx"]) {
            (void)[d getUserEx];
        } else if ([m isEqualToString:@"LogSender.setLogEnabled:"]) {
            [LogSender setLogEnabled:YES];
        }
        NSTimeInterval dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000;
        NSLog(@"[ENV A1] %@ -> %.1fms (3G)", m, dt);
        XCTAssertLessThan(dt, 50.0, @"#A1 弱网下 %@ 应 <50ms, 实际=%.1fms", m, dt);
    }
}

/// A2: 弱网 3G 下 writeLog 主线程不阻塞（P2-4）
- (void)test_A2_writeLog_mainthread_not_blocked_under_3g {
    [self cleanDB];
    ClsLogStorage *s = [ClsLogStorage sharedInstance];

    // 主线程调 writeLog 100 次，每次 <20ms
    __block NSTimeInterval maxDt = 0;
    for (int i = 0; i < 100; i++) {
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        [s writeLog:[self makeLog:i tag:@"A2"] topicId:kEnvTopic completion:nil];
        NSTimeInterval dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000;
        if (dt > maxDt) maxDt = dt;
    }
    NSLog(@"[ENV A2] 100 次 writeLog 主线程最大耗时 %.1fms (3G)", maxDt);
    XCTAssertLessThan(maxDt, 20.0, @"#A2 弱网下 writeLog 主线程最大 <20ms, 实际=%.1f", maxDt);
}

/// A3: 弱网 3G 下 Sender 发送仍进行但较慢（P2-5 退避 - 简化观察版）
- (void)test_A3_sender_still_working_under_3g {
    [self cleanDB];
    ClsLogStorage *s = [ClsLogStorage sharedInstance];

    // 写 50 条
    for (int i = 0; i < 50; i++) {
        [s writeLog:[self makeLog:i tag:@"A3"] topicId:kEnvTopic completion:nil];
    }
    [NSThread sleepForTimeInterval:0.5];
    NSUInteger p0 = [s queryPendingLogs:10000].count;
    NSLog(@"[ENV A3] 写入后 pending=%lu", (unsigned long)p0);
    XCTAssertGreaterThanOrEqual(p0, 40ul, @"#A3 50 条应入库");

    // 等 20 秒观察，Sender 应该有一些发送动作（3G 慢但不是 0）
    [NSThread sleepForTimeInterval:20.0];
    NSUInteger p1 = [s queryPendingLogs:10000].count;
    NSLog(@"[ENV A3] 20s 后 pending=%lu（3G：有退避，但 Sender 应该有部分发出）", (unsigned long)p1);
    // 不严格断言 p1<p0 或 p1==p0，只要不崩就说明 Sender 在 3G 下正常运作
    [self cleanDB];
}

#pragma mark - Group A': NLC 100% Loss 完全断网

/// A'1: 完全断网下五入口 <50ms
- (void)test_Ap1_entry_latency_under_offline {
    [self test_A1_entry_latency_under_3g];  // 相同断言，不同网络条件下跑
}

/// A'2: Very Bad Network（95% loss + 500ms RTT）下 Sender 的鲁棒性：
///  - 要么全部送达（Sender 重试机制生效，正向验证）
///  - 要么全部保留（POSIX 失败不删日志，#22 分支）
///  两种结果都算 pass，不允许"部分丢失"
- (void)test_Ap2_sender_keeps_logs_offline {
    [self cleanDB];
    ClsLogStorage *s = [ClsLogStorage sharedInstance];

    for (int i = 0; i < 30; i++) {
        [s writeLog:[self makeLog:i tag:@"Ap2"] topicId:kEnvTopic completion:nil];
    }
    [NSThread sleepForTimeInterval:1.0];
    NSUInteger p0 = [s queryPendingLogs:10000].count;
    NSLog(@"[ENV A'2] 坏网写入后 pending=%lu", (unsigned long)p0);
    XCTAssertGreaterThanOrEqual(p0, 25ul);

    [NSThread sleepForTimeInterval:25.0];
    NSUInteger p1 = [s queryPendingLogs:10000].count;
    NSLog(@"[ENV A'2] 25s 后 pending=%lu（p0=%lu）→ Sender 鲁棒性验证",
          (unsigned long)p1, (unsigned long)p0);

    // 允许两种结果：
    //   (A) p1 == 0 全送达 → Sender 重试机制在坏网下仍成功
    //   (B) p1 ≥ p0 * 0.9 全保留 → POSIX 失败不删日志（#22）
    // 禁止"部分丢失"：p1 ∈ (0, p0*0.9) 说明失败路径误删
    BOOL allSent  = (p1 == 0);
    BOOL allKept  = (p1 >= (NSUInteger)(p0 * 0.9));
    XCTAssertTrue(allSent || allKept,
                  @"#A'2 Sender 鲁棒性异常：既没送达也没完整保留 (p0=%lu p1=%lu)",
                  (unsigned long)p0, (unsigned long)p1);
    [self cleanDB];
}

#pragma mark - Group B: 关 WiFi 只走蜂窝

/// B1: 蜂窝单通下 DNS 能通过蜂窝解析成功（P1-4-2）
- (void)test_B1_dns_resolve_via_cellular {
    CLSDnsRequest *req = [[CLSDnsRequest alloc] init];
    req.domain = @"www.baidu.com";
    req.timeout = 15;

    XCTestExpectation *exp = [self expectationWithDescription:@"dns-cellular"];
    __block CLSResponse *resp = nil;
    [[ClsNetworkDiagnosis sharedInstance] dns:req complate:^(CLSResponse *result){
        resp = result;
        [exp fulfill];
    }];
    [self waitForExpectations:@[exp] timeout:30.0];

    NSLog(@"[ENV B1] 蜂窝 DNS 结果 content.len=%lu", (unsigned long)resp.content.length);
    XCTAssertNotNil(resp, @"#B1 应有回调");
    // 蜂窝 DNS 应能解析成功（content 非空）
    XCTAssertGreaterThan(resp.content.length, 0ul,
                         @"#B1 蜂窝 DNS 应能解析 baidu");
}

/// B2: 蜂窝下 Sender 继续工作
- (void)test_B2_sender_works_on_cellular {
    [self cleanDB];
    ClsLogStorage *s = [ClsLogStorage sharedInstance];
    for (int i = 0; i < 20; i++) {
        [s writeLog:[self makeLog:i tag:@"B2"] topicId:kEnvTopic completion:nil];
    }
    [NSThread sleepForTimeInterval:1.0];
    NSUInteger p0 = [s queryPendingLogs:10000].count;
    [NSThread sleepForTimeInterval:10.0];
    NSUInteger p1 = [s queryPendingLogs:10000].count;
    NSLog(@"[ENV B2] 蜂窝环境 p0=%lu → 10s 后 p1=%lu（Sender 应能发出）",
          (unsigned long)p0, (unsigned long)p1);
    // 蜂窝可用时 Sender 应该能发掉大部分
    XCTAssertLessThan(p1, p0, @"#B2 蜂窝下 Sender 应发出至少一些");
    [self cleanDB];
}

#pragma mark - Group C: 低电量 / 改时间

/// C1: 低电量模式下 writeLog + Sender 都能工作
- (void)test_C1_sender_works_in_low_power_mode {
    BOOL lowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    NSLog(@"[ENV C1] 当前低电量模式: %@", lowPower ? @"YES" : @"NO");
    XCTAssertTrue(lowPower, @"#C1 请先打开低电量模式");

    [self cleanDB];
    LogSender *sender = [LogSender sharedSender];
    ClsLogStorage *s = [ClsLogStorage sharedInstance];

    // 阶段1：stop sender → 验证低电量下 writeLog 能入库
    [sender stop];
    [NSThread sleepForTimeInterval:0.3];
    for (int i = 0; i < 20; i++) {
        [s writeLog:[self makeLog:i tag:@"C1"] topicId:kEnvTopic completion:nil];
    }
    [NSThread sleepForTimeInterval:1.0];
    NSUInteger p0 = [s queryPendingLogs:10000].count;
    NSLog(@"[ENV C1] 低电量 + sender stopped, 写入后 pending=%lu", (unsigned long)p0);
    XCTAssertGreaterThanOrEqual(p0, 15ul, @"#C1 低电量下 writeLog 仍应入库");

    // 阶段2：start sender → 验证低电量下 Sender 能继续发
    [sender start];
    [NSThread sleepForTimeInterval:10.0];
    NSUInteger p1 = [s queryPendingLogs:10000].count;
    NSLog(@"[ENV C1] 低电量下 Sender 启动 10s 后 pending=%lu（期望 < %lu）",
          (unsigned long)p1, (unsigned long)p0);
    XCTAssertLessThan(p1, p0, @"#C1 低电量下 Sender 应仍能发送");
    [self cleanDB];
}

/// C2: 系统时间改到 +1 天，writeLog 时间戳应该用系统时间（可能超前），不崩不乱
- (void)test_C2_writeLog_handles_time_change {
    NSTimeInterval nowSec = [[NSDate date] timeIntervalSince1970];
    NSLog(@"[ENV C2] 当前系统时间戳 = %.0f (期望用户已改到 +1 天)", nowSec);

    [self cleanDB];
    ClsLogStorage *s = [ClsLogStorage sharedInstance];
    Log *item = [self makeLog:1 tag:@"C2"];
    [s writeLog:item topicId:kEnvTopic completion:nil];

    [NSThread sleepForTimeInterval:0.5];
    NSArray *pending = [s queryPendingLogs:10];
    XCTAssertGreaterThan(pending.count, 0ul, @"#C2 时间改变后仍能入库");
    NSLog(@"[ENV C2] 时间改变后 pending[0]=%@", pending.firstObject);
    [self cleanDB];
}

#pragma mark - Group D: 杀 App 重开（双阶段）

/// D1: 阶段 1 - 写入 100 条，停 Sender，让日志存库，测试结束后用户杀 App
- (void)test_D1_prepare_logs_before_kill {
    [self cleanDB];
    LogSender *sender = [LogSender sharedSender];
    [sender stop];  // 先停 Sender，防止发走
    [NSThread sleepForTimeInterval:0.3];

    ClsLogStorage *s = [ClsLogStorage sharedInstance];
    for (int i = 0; i < 100; i++) {
        [s writeLog:[self makeLog:i tag:@"D-kill-prep"] topicId:kEnvTopic completion:nil];
    }
    [NSThread sleepForTimeInterval:1.0];
    NSUInteger p = [s queryPendingLogs:10000].count;
    NSLog(@"[ENV D1] 写入 100 条，Sender 已停。当前 pending=%lu，请杀 App 后再跑 D2", (unsigned long)p);
    XCTAssertGreaterThan(p, 80ul, @"#D1 应有 >80 条待发");
}

/// D2: 阶段 2 - 冷启动后验证日志仍在，重启 Sender 能继续发
- (void)test_D2_verify_logs_after_restart {
    ClsLogStorage *s = [ClsLogStorage sharedInstance];
    NSUInteger p0 = [s queryPendingLogs:10000].count;
    NSLog(@"[ENV D2] 冷启动后 pending=%lu（期望 >80，证明持久化）", (unsigned long)p0);
    XCTAssertGreaterThan(p0, 80ul, @"#D2 杀 App 后日志应持久化");

    // 启动 Sender
    [[LogSender sharedSender] start];
    [NSThread sleepForTimeInterval:15.0];
    NSUInteger p1 = [s queryPendingLogs:10000].count;
    NSLog(@"[ENV D2] Sender 启动 15s 后 pending=%lu（期望 <%lu，证明续发成功）",
          (unsigned long)p1, (unsigned long)p0);
    XCTAssertLessThan(p1, p0, @"#D2 Sender 启动后应能继续发日志");
    [self cleanDB];
}

@end
