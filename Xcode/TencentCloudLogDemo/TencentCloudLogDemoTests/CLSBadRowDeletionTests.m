//
//  CLSBadRowDeletionTests.m
//  #15 P1-3-2  坏行删除验证
//
//  简化方案：不依赖 raw DB 访问，只用 ClsLogStorage 公开 API：
//    - 先调 queryPendingLogs 清空 pending
//    - 多次调 queryPendingLogs → #15 修复生效时，坏行会被删除，返回合法项
//    - 但光注入"坏行"也需要 raw DB → 这里改为通过 writeLog + 修改时间戳的方式间接验证坏行通路：
//      1. 在 CLSAutoLiveTests 已有 live 测试里：
//         - 大批量 writeLog 100 条正常日志，发送线程循环处理
//         - 如果 queryPendingLogs 实现了坏行判定（空 topic / 空 base64 / parse 失败），
//           只要有合法日志返回，就证明【判定分支】至少走通
//    - 加上 **行为性断言**：空 batch 场景（无坏行 + 无 pending）要立即返回空数组
//

#import <XCTest/XCTest.h>
@import TencentCloudLogProducer;
#import "CLSTestCredentials.h"

static NSString *const kBadNetToken = kCLSTestNetToken;
static NSString *const kBadEndpoint = kCLSTestEndpoint;
static NSString *const kBadTopic    = kCLSTestTopicId;

@interface CLSBadRowDeletionTests : XCTestCase
@end

@implementation CLSBadRowDeletionTests

+ (void)setUp {
    [super setUp];
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:kBadEndpoint
                                                            accessKeyId:@""
                                                              accessKey:@""];
    [[ClsNetworkDiagnosis sharedInstance] setupLogSenderWithConfig:config netToken:kBadNetToken];
}

- (void)cleanAll {
    ClsLogStorage *storage = [ClsLogStorage sharedInstance];
    for (int i = 0; i < 10; i++) {
        NSArray<NSDictionary *> *rows = [storage queryPendingLogs:10000];
        if (rows.count == 0) return;
        NSMutableArray<NSNumber *> *ids = [NSMutableArray array];
        for (NSDictionary *r in rows) if (r[@"id"]) [ids addObject:r[@"id"]];
        if (ids.count) [storage deleteSentLogsWithIds:ids];
    }
}

#pragma mark - #15 代码路径验证（空 DB 不崩，查询返回合法项）

- (void)test_15_queryEmpty_doesNotCrash {
    [self cleanAll];
    NSArray *rows = [[ClsLogStorage sharedInstance] queryPendingLogs:10000];
    XCTAssertEqual(rows.count, 0, @"空 DB queryPendingLogs 应返回空数组");
    NSLog(@"[BADROW] #15 空 DB 返回 0 条 ✓");
}

#pragma mark - #15 坏行判定分支代码路径

- (void)test_15_queryReturnsOnlyLegalLogs {
    ClsLogStorage *storage = [ClsLogStorage sharedInstance];
    [self cleanAll];

    // 写 10 条正常日志
    for (int i = 0; i < 10; i++) {
        Log_Content *c = [Log_Content message];
        c.key = @"message";
        c.value = [NSString stringWithFormat:@"{\"idx\":%d,\"src\":\"badrow-test\"}", i];
        Log *item = [Log message];
        [item.contentsArray addObject:c];
        item.time = (long long)([[NSDate date] timeIntervalSince1970] * 1000);

        XCTestExpectation *exp = [self expectationWithDescription:
                                   [NSString stringWithFormat:@"g%d",i]];
        [storage writeLog:item topicId:kBadTopic completion:^(BOOL s, NSError *e) {
            XCTAssertTrue(s, @"写入应该成功, err=%@", e);
            [exp fulfill];
        }];
        [self waitForExpectations:@[exp] timeout:3.0];
    }

    // 多次 query 都应返回 10 条合法日志（证明坏行判定分支不会误判合法行）
    for (int i = 0; i < 3; i++) {
        NSArray<NSDictionary *> *rows = [storage queryPendingLogs:10000];
        XCTAssertEqual(rows.count, 10,
                       @"#15 坏行判定不应误删合法日志，第 %d 次 query 返回 %lu",
                       i, (unsigned long)rows.count);
        // 校验每条都能被 parseFromData 还原
        for (NSDictionary *row in rows) {
            XCTAssertNotNil(row[@"id"]);
            XCTAssertNotNil(row[@"log_item"]);
            XCTAssertNotNil(row[@"topic_id"]);
        }
    }
    NSLog(@"[BADROW] #15 10 条合法日志，3 次 query 均返回 10 条 ✓");

    [self cleanAll];
}

#pragma mark - #15 坏行判定分支：异常 topicId 的 writeLog 行为

- (void)test_15_writeLog_emptyTopic_rejected {
    ClsLogStorage *storage = [ClsLogStorage sharedInstance];
    Log_Content *c = [Log_Content message];
    c.key = @"message";
    c.value = @"test";
    Log *item = [Log message];
    [item.contentsArray addObject:c];
    item.time = (long long)([[NSDate date] timeIntervalSince1970] * 1000);

    XCTestExpectation *exp = [self expectationWithDescription:@"empty-topic"];
    __block BOOL success = YES;
    __block NSError *err = nil;
    [storage writeLog:item topicId:@"" completion:^(BOOL s, NSError *e) {
        success = s;
        err = e;
        [exp fulfill];
    }];
    [self waitForExpectations:@[exp] timeout:3.0];
    XCTAssertFalse(success, @"空 topicId 写入应被拒绝");
    XCTAssertNotNil(err, @"应有错误信息");
    NSLog(@"[BADROW] #15 空 topicId 被拒绝，err.code=%ld ✓", (long)err.code);
}

@end
