#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <sqlite3.h>
#import <TencentCloudLogProducer/ClsLogStorage.h>
#import <TencentCloudLogProducer/ClsLogSender.h>
#import <TencentCloudLogProducer/ClsLogs.pbobjc.h>
#import <FMDB/FMDB.h>

static NSInteger gInjectedFailuresRemaining = 0;
static NSString *gInjectedSQLSubstring = nil;

@interface FMDatabase (CLSInject)
@end

@implementation FMDatabase (CLSInject)
- (BOOL)clsInject_executeUpdate:(NSString *)sql
                          error:(NSError * _Nullable __autoreleasing *)outErr
           withArgumentsInArray:(NSArray *)arrayArgs
                   orDictionary:(NSDictionary *)dictionaryArgs
                       orVAList:(va_list)args {
    BOOL hit = YES;
    if (gInjectedSQLSubstring.length > 0) {
        hit = ([sql rangeOfString:gInjectedSQLSubstring].location != NSNotFound);
    }
    if (hit && gInjectedFailuresRemaining > 0) {
        gInjectedFailuresRemaining--;
        NSLog(@"[CLSInject] fail injected, remaining=%ld sql=%@", (long)gInjectedFailuresRemaining, sql);
        if (outErr) {
            *outErr = [NSError errorWithDomain:@"CLSInject" code:SQLITE_IOERR userInfo:@{NSLocalizedDescriptionKey:@"injected failure"}];
        }
        return NO;
    }
    return [self clsInject_executeUpdate:sql
                                   error:outErr
                    withArgumentsInArray:arrayArgs
                            orDictionary:dictionaryArgs
                                orVAList:args];
}
@end

@interface CLSDeleteSafetyTests : XCTestCase
@end

@implementation CLSDeleteSafetyTests

+ (void)setUp {
    [super setUp];
    SEL orig = @selector(executeUpdate:error:withArgumentsInArray:orDictionary:orVAList:);
    SEL mock = @selector(clsInject_executeUpdate:error:withArgumentsInArray:orDictionary:orVAList:);
    Method m1 = class_getInstanceMethod([FMDatabase class], orig);
    Method m2 = class_getInstanceMethod([FMDatabase class], mock);
    if (m1 && m2) {
        method_exchangeImplementations(m1, m2);
    }
}

- (void)setUp {
    [super setUp];
    gInjectedFailuresRemaining = 0;
    gInjectedSQLSubstring = nil;

    LogSender *sender = [LogSender sharedSender];
    [sender stop];
    NSThread *workThread = [sender valueForKey:@"workThread"];
    NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + 3.0;
    while (workThread && !workThread.isFinished && [NSDate timeIntervalSinceReferenceDate] < deadline) {
        [NSThread sleepForTimeInterval:0.02];
    }

    ClsLogStorage *storage = [ClsLogStorage sharedInstance];
    dispatch_queue_t writeQueue = [storage valueForKey:@"writeQueue"];
    if (writeQueue) {
        dispatch_sync(writeQueue, ^{ /* flush */ });
    }

    FMDatabaseQueue *q = [storage valueForKey:@"dbQueue"];
    XCTAssertNotNil(q);
    [q inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"DELETE FROM cls_log_table"];
        [db executeUpdate:@"DELETE FROM sqlite_sequence WHERE name='cls_log_table'"];
    }];
    [storage setValue:@YES forKey:@"isDbWritable"];
    [storage setValue:@0 forKey:@"consecutiveShortDeleteCount"];
}

- (void)tearDown {
    gInjectedFailuresRemaining = 0;
    gInjectedSQLSubstring = nil;
    [[ClsLogStorage sharedInstance] setValue:@YES forKey:@"isDbWritable"];
    [super tearDown];
}

#pragma mark - helpers

- (FMDatabaseQueue *)dbQueue {
    return [[ClsLogStorage sharedInstance] valueForKey:@"dbQueue"];
}

- (void)insertRawLogWithId:(int64_t)forcedId topicId:(NSString *)topicId {
    Log *log = [[Log alloc] init];
    Log_Content *c = [[Log_Content alloc] init];
    c.key = @"k";
    c.value = @"v";
    [log.contentsArray addObject:c];
    log.time = (int64_t)[[NSDate date] timeIntervalSince1970];
    NSString *base64 = [[log data] base64EncodedStringWithOptions:0];

    [self.dbQueue inDatabase:^(FMDatabase *db) {
        NSString *sql = @"INSERT INTO cls_log_table (_id, log_item_data, topic_id, create_time) VALUES (?, ?, ?, ?)";
        BOOL ok = [db executeUpdate:sql, @(forcedId), base64, topicId, @((int64_t)[[NSDate date] timeIntervalSince1970] * 1000)];
        XCTAssertTrue(ok, @"raw insert failed: %@", db.lastErrorMessage);
    }];
}

- (NSUInteger)rowCount {
    __block NSUInteger n = 0;
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"SELECT COUNT(*) AS c FROM cls_log_table"];
        if ([rs next]) n = (NSUInteger)[rs longLongIntForColumn:@"c"];
        [rs close];
    }];
    return n;
}

#pragma mark - cases

- (void)testCase01_L0_QueryReturnsFull64BitId {
    int64_t bigId = (int64_t)INT32_MAX + 42;
    [self insertRawLogWithId:bigId topicId:@"t"];

    NSArray *rows = [[ClsLogStorage sharedInstance] queryPendingLogs:10];
    XCTAssertEqual(rows.count, 1u);
    NSNumber *gotId = rows.firstObject[@"id"];
    XCTAssertNotNil(gotId);
    XCTAssertEqual(gotId.longLongValue, bigId);
    XCTAssertGreaterThan(gotId.longLongValue, (long long)INT32_MAX);
}

- (void)testCase02_L0_DeleteOnLargeIdActuallyHits {
    int64_t bigId = (int64_t)INT32_MAX + 999;
    [self insertRawLogWithId:bigId topicId:@"t"];
    XCTAssertEqual([self rowCount], 1u);

    BOOL ok = [[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[@(bigId)]];
    XCTAssertTrue(ok);
    XCTAssertEqual([self rowCount], 0u);
    XCTAssertTrue([[ClsLogStorage sharedInstance] isDbWritable]);
}

- (void)testCase03_L1_DeleteEmptyIdsReturnsYES {
    XCTAssertTrue([[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[]]);
    XCTAssertTrue([[ClsLogStorage sharedInstance] isDbWritable]);
}

- (void)testCase04_L1_HappyPathReturnsYES {
    [self insertRawLogWithId:1 topicId:@"t"];
    [self insertRawLogWithId:2 topicId:@"t"];
    BOOL ok = [[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[@1, @2]];
    XCTAssertTrue(ok);
    XCTAssertEqual([self rowCount], 0u);
    XCTAssertTrue([[ClsLogStorage sharedInstance] isDbWritable]);
}

- (void)testCase05_EvictionRace_ChangesLessThanExpected_NoFuse {
    [self insertRawLogWithId:100 topicId:@"t"];
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"DELETE FROM cls_log_table WHERE _id = 100"];
    }];
    XCTAssertEqual([self rowCount], 0u);

    BOOL ok = [[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[@100]];
    XCTAssertTrue(ok);
    XCTAssertTrue([[ClsLogStorage sharedInstance] isDbWritable]);
}

- (void)testCase06_L2_TwoTransientFailures_ThenSucceed {
    [self insertRawLogWithId:7 topicId:@"t"];

    gInjectedSQLSubstring = @"DELETE FROM cls_log_table";
    gInjectedFailuresRemaining = 2;

    NSDate *t0 = [NSDate date];
    BOOL ok = [[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[@7]];
    NSTimeInterval dt = [[NSDate date] timeIntervalSinceDate:t0];

    XCTAssertTrue(ok);
    XCTAssertTrue([[ClsLogStorage sharedInstance] isDbWritable]);
    XCTAssertEqual([self rowCount], 0u);
    XCTAssertGreaterThan(dt, 0.18);
    XCTAssertLessThan(dt, 1.5);
    XCTAssertEqual(gInjectedFailuresRemaining, 0);
}

- (void)testCase07_L3_AllRetriesExhaust_TripsFuse_ReturnsNO {
    [self insertRawLogWithId:8 topicId:@"t"];

    gInjectedSQLSubstring = @"DELETE FROM cls_log_table";
    gInjectedFailuresRemaining = 4;

    BOOL ok = [[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[@8]];
    XCTAssertFalse(ok);
    XCTAssertFalse([[ClsLogStorage sharedInstance] isDbWritable]);
    XCTAssertEqual([self rowCount], 1u);
}

- (void)testCase08_L3_FusedQueryReturnsEmpty {
    [self insertRawLogWithId:9 topicId:@"t"];
    [[ClsLogStorage sharedInstance] setValue:@NO forKey:@"isDbWritable"];

    NSArray *rows = [[ClsLogStorage sharedInstance] queryPendingLogs:10];
    XCTAssertEqual(rows.count, 0u);
    XCTAssertEqual([self rowCount], 1u);
}

- (void)testCase09_L3_FusedDeleteReturnsNO {
    [self insertRawLogWithId:10 topicId:@"t"];
    [[ClsLogStorage sharedInstance] setValue:@NO forKey:@"isDbWritable"];

    BOOL ok = [[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[@10]];
    XCTAssertFalse(ok);
    XCTAssertEqual([self rowCount], 1u);
}

#pragma mark - 3.3.1 补丁：changes < expected 阈值化

// Case10：持续 short delete（SQL 成功但行不存在，模拟 B 类 DB 异常）
// 不依赖注入错误：直接对不存在的 _id 做 DELETE，changes 恒为 0。
// 前 2 次视为"偶发 evict race" → 容忍返回 YES；第 3 次达到阈值 → 返回 NO 并熔断。
- (void)testCase10_PersistentShortDelete_TripsFuseAtThreshold {
    ClsLogStorage *storage = [ClsLogStorage sharedInstance];
    NSArray *fakeIds = @[@99991, @99992, @99993];  // 这些 _id 在库里不存在
    XCTAssertEqual([self rowCount], 0u);

    // 1st short delete：计数 1，容忍
    BOOL ok1 = [storage deleteSentLogsWithIds:fakeIds];
    XCTAssertTrue(ok1, @"1st short delete should be tolerated");
    XCTAssertTrue([storage isDbWritable]);
    XCTAssertEqual([[storage valueForKey:@"consecutiveShortDeleteCount"] integerValue], 1);

    // 2nd short delete：计数 2，容忍
    BOOL ok2 = [storage deleteSentLogsWithIds:fakeIds];
    XCTAssertTrue(ok2, @"2nd short delete should be tolerated");
    XCTAssertTrue([storage isDbWritable]);
    XCTAssertEqual([[storage valueForKey:@"consecutiveShortDeleteCount"] integerValue], 2);

    // 3rd short delete：计数达阈值 3，熔断
    BOOL ok3 = [storage deleteSentLogsWithIds:fakeIds];
    XCTAssertFalse(ok3, @"3rd short delete should trip the fuse");
    XCTAssertFalse([storage isDbWritable], @"isDbWritable should be NO after fuse");

    // 熔断后 queryPendingLogs 必须返回空（防止 workLoop 重传风暴）
    [self insertRawLogWithId:50001 topicId:@"t"];  // 走 writeLog 不受熔断影响
    NSArray *pending = [storage queryPendingLogs:10];
    XCTAssertEqual(pending.count, 0u, @"query must be blocked after fuse");
}

// Case11：偶发 short delete 被真·命中 reset，不触发熔断
// 模拟真·evict race 场景：worker 偶尔遇到 1 次 short delete，后续一次正常 delete 把计数复位。
- (void)testCase11_OccasionalShortDelete_ResetByFullHit {
    ClsLogStorage *storage = [ClsLogStorage sharedInstance];
    [self insertRawLogWithId:60001 topicId:@"t"];
    [self insertRawLogWithId:60002 topicId:@"t"];

    // 第 1 次 short delete：请求 (60001, 99999)，只命中 60001，changes=1 < expected=2
    BOOL ok1 = [storage deleteSentLogsWithIds:@[@60001, @99999]];
    XCTAssertTrue(ok1, @"short delete within threshold should return YES");
    XCTAssertTrue([storage isDbWritable]);
    XCTAssertEqual([[storage valueForKey:@"consecutiveShortDeleteCount"] integerValue], 1);
    XCTAssertEqual([self rowCount], 1u);  // 60002 还在

    // 第 2 次 full delete：请求 (60002)，完全命中 → 计数应复位为 0
    BOOL ok2 = [storage deleteSentLogsWithIds:@[@60002]];
    XCTAssertTrue(ok2);
    XCTAssertTrue([storage isDbWritable]);
    XCTAssertEqual([[storage valueForKey:@"consecutiveShortDeleteCount"] integerValue], 0,
                   @"full hit must reset the consecutive counter");
    XCTAssertEqual([self rowCount], 0u);

    // 继续 2 次 short delete：由于前面已复位，计数从 1 开始，仍 < 阈值 → 不熔断
    [storage deleteSentLogsWithIds:@[@77771]];
    [storage deleteSentLogsWithIds:@[@77772]];
    XCTAssertTrue([storage isDbWritable], @"should not trip because counter was reset mid-way");
    XCTAssertEqual([[storage valueForKey:@"consecutiveShortDeleteCount"] integerValue], 2);
}

@end
