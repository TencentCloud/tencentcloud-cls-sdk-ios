//
//  CLSAirplaneModeTests.m
//  说明：原飞行模式需求无法与 Xcode 真机调试同时存在（证书验证需联网）。
//  改为"endpoint 指到不可达保留地址"模拟 POSIX 错误，走的代码路径完全相同：
//    - 发送 → NSURLSession 底层 → connect → ENETUNREACH/EHOSTUNREACH/ETIMEDOUT
//    - 这些都是 NSPOSIXErrorDomain，正是 #22 修复 ClsNetworkTool.m 的目标域
//
//  覆盖映射：
//  - #22 P1-2-1  POSIX 错误码不删日志
//  - #27 P0-6-2  断网下 nil completion 都不崩
//

#import <XCTest/XCTest.h>
@import TencentCloudLogProducer;
#import "CLSTestCredentials.h"

static NSString *const kAirNetToken = kCLSTestNetToken;
// 10.255.255.1 为 RFC1918 保留私有地址，默认路由不可达 → connect 产生 POSIX ENETUNREACH/ETIMEDOUT
static NSString *const kUnreachableEndpoint = @"10.255.255.1";
static NSString *const kAirSecretId  = kCLSTestSecretId;
static NSString *const kAirSecretKey = kCLSTestSecretKey;
static NSString *const kAirTopic     = kCLSTestTopicId;

@interface CLSAirplaneModeTests : XCTestCase
@end

@implementation CLSAirplaneModeTests

+ (void)setUp {
    [super setUp];
    // 让 diagnosis 单例保持正常网络能力
    ClsLogSenderConfig *normal = [ClsLogSenderConfig configWithEndpoint:kCLSTestEndpoint
                                                            accessKeyId:kAirSecretId
                                                              accessKey:kAirSecretKey];
    [[ClsNetworkDiagnosis sharedInstance] setupLogSenderWithConfig:normal netToken:kAirNetToken];

    // LogSender 单例改成不可达 endpoint，让所有后续发送都 POSIX fail
    ClsLogSenderConfig *bad = [ClsLogSenderConfig configWithEndpoint:kUnreachableEndpoint
                                                         accessKeyId:kAirSecretId
                                                           accessKey:kAirSecretKey];
    [[LogSender sharedSender] setConfig:bad];
    NSLog(@"[AIR] +setUp done, LogSender endpoint set to unreachable=%@", kUnreachableEndpoint);
}

#pragma mark - #22 POSIX 错误码不删日志（核心用例）

- (void)test_22_posix_error_keeps_logs_in_db {
    ClsLogStorage *storage = [ClsLogStorage sharedInstance];
    LogSender *sender = [LogSender sharedSender];

    // 1. 清空当前 pending（防止其他测试残留干扰）
    NSArray<NSDictionary *> *pre = [storage queryPendingLogs:10000];
    NSMutableArray<NSNumber *> *preIds = [NSMutableArray array];
    for (NSDictionary *row in pre) {
        if (row[@"id"]) [preIds addObject:row[@"id"]];
    }
    if (preIds.count) {
        [storage deleteSentLogsWithIds:preIds];
    }
    NSUInteger beforeCount = [storage queryPendingLogs:10000].count;
    NSLog(@"[AIR] #22 清空后 pending=%lu", (unsigned long)beforeCount);
    XCTAssertEqual(beforeCount, 0, @"前置清理后 DB 应为空");

    // 2. 启动 sender（将不断尝试把日志发到不可达 10.255.255.1）
    [sender start];

    // 3. 写入 20 条带独特 marker 的日志
    NSString *marker = [NSString stringWithFormat:@"posix-%ld",
                        (long)([[NSDate date] timeIntervalSince1970])];
    for (int i = 0; i < 20; i++) {
        Log_Content *c = [Log_Content message];
        c.key = @"message";
        c.value = [NSString stringWithFormat:@"{\"idx\":%d,\"src\":\"%@\"}", i, marker];
        Log *item = [Log message];
        [item.contentsArray addObject:c];
        item.time = (long long)([[NSDate date] timeIntervalSince1970] * 1000);

        XCTestExpectation *exp = [self expectationWithDescription:
                                   [NSString stringWithFormat:@"w%d", i]];
        [storage writeLog:item topicId:kAirTopic completion:^(BOOL s, NSError *e) {
            XCTAssertTrue(s, @"写入应该成功, err=%@", e);
            [exp fulfill];
        }];
        [self waitForExpectations:@[exp] timeout:3.0];
    }

    NSUInteger afterWrite = [storage queryPendingLogs:10000].count;
    NSLog(@"[AIR] #22 写入 20 条后 pending=%lu", (unsigned long)afterWrite);
    XCTAssertGreaterThanOrEqual(afterWrite, 20, @"20 条应全部入库");

    // 4. 等 sender 多次尝试发送（30 秒内 ClsNetworkTool 可以触发多批次 POSIX fail）
    NSLog(@"[AIR] #22 等待 30 秒让 sender 发送失败多次...");
    [NSThread sleepForTimeInterval:30.0];

    // 5. 核心断言：pending 条数**不少于**写入数
    NSUInteger afterSendFailed = [storage queryPendingLogs:10000].count;
    NSLog(@"[AIR] #22 发送失败等待后 pending=%lu (期望 >= 20)",
          (unsigned long)afterSendFailed);
    XCTAssertGreaterThanOrEqual(afterSendFailed, 20,
                                @"#22 修复后：POSIX 错误不删除日志，20 条应仍在 DB。"
                                @"修复前（ClsNetworkTool.m 的非 NSURLErrorDomain 分支）"
                                @"这些日志会被当作非网络错误从 DB 删除。");
}

#pragma mark - #27 补：endpoint 不可达状态下 nil completion 不崩

- (void)test_27_unreachable_pingv2_nilCompletion_doesNotCrash {
    CLSPingRequest *req = [[CLSPingRequest alloc] init];
    req.domain = @"www.baidu.com";

    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wnonnull"
    XCTAssertNoThrow(([[ClsNetworkDiagnosis sharedInstance] pingv2:req complate:nil]),
                     @"#27 pingv2 nil completion 不应崩溃");
    #pragma clang diagnostic pop
    [NSThread sleepForTimeInterval:3.0];
    NSLog(@"[AIR] #27 pingv2 nil completion 已过");
}

- (void)test_27_unreachable_mtr_nilCompletion_doesNotCrash {
    CLSMtrRequest *req = [[CLSMtrRequest alloc] init];
    req.domain = @"www.baidu.com";

    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wnonnull"
    XCTAssertNoThrow(([[ClsNetworkDiagnosis sharedInstance] mtr:req complate:nil]),
                     @"#27 mtr nil completion 不应崩溃");
    #pragma clang diagnostic pop
    [NSThread sleepForTimeInterval:5.0];
    NSLog(@"[AIR] #27 mtr nil completion 已过");
}

#pragma mark - 收尾：恢复 LogSender endpoint

- (void)test_zz_restore_endpoint {
    ClsLogSenderConfig *normal = [ClsLogSenderConfig configWithEndpoint:kCLSTestEndpoint
                                                            accessKeyId:kAirSecretId
                                                              accessKey:kAirSecretKey];
    [[LogSender sharedSender] setConfig:normal];
    NSLog(@"[AIR] zz 恢复 LogSender endpoint 到正常地址");
}

@end
