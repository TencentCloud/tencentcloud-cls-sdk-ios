#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <sqlite3.h>
#import <TencentCloudLogProducer/ClsLogStorage.h>
#import <TencentCloudLogProducer/ClsLogSender.h>
#import <TencentCloudLogProducer/ClsLogs.pbobjc.h>
#import <FMDB/FMDB.h>
#import <OCMock/OCMock.h>
#import <TencentCloudLogProducer/CLSNetworkTool.h>
#import <string.h>

static NSInteger gInjectedFailuresRemaining = 0;
static NSString *gInjectedSQLSubstring = nil;

@interface FMDatabase (CLSPrivateTestAccess)
- (BOOL)executeUpdate:(NSString *)sql
                 error:(NSError * _Nullable __autoreleasing *)outErr
  withArgumentsInArray:(NSArray *)arrayArgs
          orDictionary:(NSDictionary *)dictionaryArgs
              orVAList:(va_list)args;
@end

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

static sqlite3_vfs gCommitTestVFS;
static sqlite3_vfs *gBaseVFS;
static sqlite3_io_methods gWalMethods;
static const sqlite3_io_methods *gBaseWalMethods;
static NSInteger gWalFailuresRemaining;
static int gWalFailureCode = SQLITE_FULL;
static BOOL gDenyConfiguration;
static NSUInteger gWalFailures;
static sqlite3 *gCommitTestDB;
static BOOL gDenyBegin;
static BOOL gDenyCommit;
static BOOL gDenyRollback;
static NSUInteger gDeleteFullHits;
static NSMutableArray<NSDictionary *> *gCommitResults;

// Faults only the private test VFS's WAL writes; the host disk is never filled.
static int CLSFailWalWrite(sqlite3_file *file, const void *buffer, int size, sqlite3_int64 offset) {
    if (gWalFailuresRemaining > 0) {
        gWalFailuresRemaining--;
        gWalFailures++;
        return gWalFailureCode;
    }
    return gBaseWalMethods->xWrite(file, buffer, size, offset);
}

static int CLSCommitTestOpen(sqlite3_vfs *vfs, const char *path, sqlite3_file *file, int flags, int *outFlags) {
    int rc = gBaseVFS->xOpen(gBaseVFS, path, file, flags, outFlags);
    if (rc == SQLITE_OK && (flags & SQLITE_OPEN_WAL)) {
        gBaseWalMethods = file->pMethods;
        gWalMethods = *gBaseWalMethods;
        gWalMethods.xWrite = CLSFailWalWrite;
        file->pMethods = &gWalMethods;
    }
    return rc;
}

static int CLSAuthorizeTransaction(void *context, int action, const char *operation,
                                   const char *arg2, const char *database, const char *trigger) {
    if (gDenyConfiguration && action == SQLITE_PRAGMA && operation &&
        strcmp(operation, "synchronous") == 0) return SQLITE_DENY;
    if (action == SQLITE_TRANSACTION && operation) {
        if ((gDenyBegin && strcmp(operation, "BEGIN") == 0) ||
            (gDenyCommit && strcmp(operation, "COMMIT") == 0) ||
            (gDenyRollback && strcmp(operation, "ROLLBACK") == 0)) {
            return SQLITE_DENY;
        }
    }
    return SQLITE_OK;
}

@interface FMDatabase (CLSCommitObserve)
@end
@implementation FMDatabase (CLSCommitObserve)
- (BOOL)clsCommit_executeUpdate:(NSString *)sql
                         error:(NSError * _Nullable __autoreleasing *)outErr
          withArgumentsInArray:(NSArray *)arrayArgs
                  orDictionary:(NSDictionary *)dictionaryArgs
                      orVAList:(va_list)args {
    BOOL ok = [self clsCommit_executeUpdate:sql error:outErr withArgumentsInArray:arrayArgs
                              orDictionary:dictionaryArgs orVAList:args];
    if (self.sqliteHandle == gCommitTestDB) {
        if ([sql hasPrefix:@"DELETE FROM cls_log_table WHERE"] && ok && self.changes == 1) {
            gDeleteFullHits++;
        }
        if ([sql.lowercaseString hasPrefix:@"commit"]) {
            NSDictionary *state = @{@"ok": @(ok), @"code": @(self.lastErrorCode),
                                    @"autocommit": @(sqlite3_get_autocommit(self.sqliteHandle))};
            [gCommitResults addObject:state];
            NSLog(@"[CLSCommitProbe] %@ fullHits=%lu walFailures=%lu", state,
                  (unsigned long)gDeleteFullHits, (unsigned long)gWalFailures);
        }
    }
    return ok;
}
@end

@interface ClsLogStorage (CLSCommitTestAccess)
- (void)setupDatabase;
@end
@interface LogSender (CLSCommitTestAccess)
- (void)sendAllPendingOnThread:(NSThread *)thread;
- (BOOL)sendBatchLogs:(NSArray<NSDictionary *> *)logs config:(ClsLogSenderConfig *)config;
@end

@interface CLSBoundedCommitSender : LogSender
@property (nonatomic) NSUInteger batches;
@property (nonatomic, strong) NSMutableArray<NSArray *> *sentIds;
@end
@implementation CLSBoundedCommitSender
- (BOOL)sendBatchLogs:(NSArray<NSDictionary *> *)logs config:(ClsLogSenderConfig *)config {
    if (self.batches >= 6) return NO;
    self.batches++;
    [self.sentIds addObject:[logs valueForKey:@"id"]];
    return [super sendBatchLogs:logs config:config];
}
@end

@interface CLSCommitSafetyTests : XCTestCase
@property (nonatomic, strong) FMDatabaseQueue *originalQueue;
@property (nonatomic, strong) FMDatabaseQueue *queue;
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) id networkMock;
@end

@implementation CLSCommitSafetyTests
+ (void)setUp {
    [super setUp];
    gBaseVFS = sqlite3_vfs_find(NULL);
    gCommitTestVFS = *gBaseVFS;
    gCommitTestVFS.zName = "cls-commit-safety";
    gCommitTestVFS.pNext = NULL;
    gCommitTestVFS.xOpen = CLSCommitTestOpen;
    NSAssert(sqlite3_vfs_register(&gCommitTestVFS, 0) == SQLITE_OK, @"test VFS registration failed");
    method_exchangeImplementations(
        class_getInstanceMethod(FMDatabase.class, @selector(executeUpdate:error:withArgumentsInArray:orDictionary:orVAList:)),
        class_getInstanceMethod(FMDatabase.class, @selector(clsCommit_executeUpdate:error:withArgumentsInArray:orDictionary:orVAList:)));
}

+ (void)tearDown {
    method_exchangeImplementations(
        class_getInstanceMethod(FMDatabase.class, @selector(executeUpdate:error:withArgumentsInArray:orDictionary:orVAList:)),
        class_getInstanceMethod(FMDatabase.class, @selector(clsCommit_executeUpdate:error:withArgumentsInArray:orDictionary:orVAList:)));
    sqlite3_vfs_unregister(&gCommitTestVFS);
    [super tearDown];
}

- (void)setUp {
    [super setUp];
    gWalFailuresRemaining = 0;
    gWalFailureCode = SQLITE_FULL;
    gDenyConfiguration = NO;
    gWalFailures = 0;
    gDenyBegin = gDenyCommit = gDenyRollback = NO;
    gDeleteFullHits = 0;
    gCommitResults = [NSMutableArray array];
    LogSender *sender = [LogSender sharedSender];
    NSThread *worker = [sender valueForKey:@"workThread"];
    [sender stop];
    NSLock *sendLock = [sender valueForKey:@"sendLock"];
    [sendLock lock];
    [sendLock unlock];
    XCTAssertTrue(!worker || worker.isCancelled);
    ClsLogStorage *storage = [ClsLogStorage sharedInstance];
    dispatch_sync([storage valueForKey:@"writeQueue"], ^{});
    self.originalQueue = [storage valueForKey:@"dbQueue"];
    self.directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:self.directory
                                           withIntermediateDirectories:YES attributes:nil error:nil]);
    self.path = [self.directory stringByAppendingPathComponent:@"commit.db"];
    self.queue = [[FMDatabaseQueue alloc] initWithPath:self.path
                                               flags:SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
                                                 vfs:@"cls-commit-safety"];
    XCTAssertNotNil(self.queue);
    [storage setValue:self.queue forKey:@"dbQueue"];
    [storage setValue:@YES forKey:@"isDbWritable"];
    [storage setValue:@0 forKey:@"consecutiveShortDeleteCount"];
    [storage setupDatabase];
    [self.queue inDatabase:^(FMDatabase *db) {
        gCommitTestDB = db.sqliteHandle;
        XCTAssertEqualObjects([db stringForQuery:@"PRAGMA journal_mode"], @"wal");
        XCTAssertEqual(sqlite3_set_authorizer(db.sqliteHandle, CLSAuthorizeTransaction, NULL), SQLITE_OK);
        Log *log = [[Log alloc] init];
        log.time = 1793692898293;
        Log_Content *content = [[Log_Content alloc] init];
        content.key = @"event";
        content.value = @"storage-full";
        [log.contentsArray addObject:content];
        BOOL inserted = [db executeUpdate:@"INSERT INTO cls_log_table (_id, log_item_data, topic_id, create_time) VALUES (1, ?, 'test-topic', 1)",
                         [[log data] base64EncodedStringWithOptions:0]];
        XCTAssertTrue(inserted);
    }];
}

- (void)tearDown {
    [self.networkMock stopMocking];
    self.networkMock = nil;
    gWalFailuresRemaining = 0;
    gDenyConfiguration = NO;
    gDenyBegin = gDenyCommit = gDenyRollback = NO;
    ClsLogStorage *storage = [ClsLogStorage sharedInstance];
    dispatch_sync([storage valueForKey:@"writeQueue"], ^{});
    [self.queue inDatabase:^(FMDatabase *db) {
        sqlite3_set_authorizer(db.sqliteHandle, NULL, NULL);
        if (!sqlite3_get_autocommit(db.sqliteHandle)) [db rollback];
    }];
    gCommitTestDB = NULL;
    [self.queue close];
    [storage setValue:self.originalQueue forKey:@"dbQueue"];
    [storage setValue:@YES forKey:@"isDbWritable"];
    [storage setValue:@0 forKey:@"consecutiveShortDeleteCount"];
    [storage setValue:@NO forKey:@"needsConnectionConfiguration"];
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:self.directory error:nil]);
    [super tearDown];
}

- (NSUInteger)committedRowCount {
    FMDatabase *reader = [FMDatabase databaseWithPath:self.path];
    XCTAssertTrue([reader open]);
    FMResultSet *rows = [reader executeQuery:@"SELECT COUNT(*) AS row_count FROM cls_log_table"];
    XCTAssertNotNil(rows);
    BOOL hasRow = [rows next];
    XCTAssertTrue(hasRow);
    XCTAssertFalse(reader.hadError);
    NSUInteger count = hasRow ? (NSUInteger)[rows longLongIntForColumn:@"row_count"] : NSNotFound;
    [rows close];
    [reader close];
    return count;
}

- (void)assertNoActiveTransaction {
    [self.queue inDatabase:^(FMDatabase *db) {
        XCTAssertEqual(sqlite3_get_autocommit(db.sqliteHandle), 1);
    }];
}

- (void)testWALFullAtCommitStopsSuccessfulHTTPReplay {
    gWalFailuresRemaining = NSIntegerMax;
    __block NSUInteger requests = 0;
    CLSSendResult *response = [[CLSSendResult alloc] init];
    response.statusCode = 200;
    response.requestID = @"controlled-200";
    self.networkMock = OCMClassMock(CLSNetworkTool.class);
    OCMStub([self.networkMock isNetworkAvailable]).andReturn(YES);
    OCMStub([self.networkMock sendPostRequestSyncWithUrl:[OCMArg any] headers:[OCMArg any]
                                                  body:[OCMArg any] option:[OCMArg any]])
        .andDo(^(NSInvocation *invocation) { requests++; }).andReturn(response);
    CLSBoundedCommitSender *sender = [[CLSBoundedCommitSender alloc] init];
    sender.sentIds = [NSMutableArray array];
    [sender setConfig:[ClsLogSenderConfig configWithEndpoint:@"test.invalid"
                                               accessKeyId:@"test-id" accessKey:@"test-key"]];
    [sender sendAllPendingOnThread:NSThread.currentThread];
    NSLog(@"[CLSCommitProbe] requests=%lu ids=%@ fullHits=%lu commits=%@", (unsigned long)requests,
          sender.sentIds, (unsigned long)gDeleteFullHits, gCommitResults);
    XCTAssertEqual(requests, 1u, @"SQL retries must not resend an HTTP-200 batch");
    XCTAssertEqual(gDeleteFullHits, 4u);
    XCTAssertEqual(gCommitResults.count, 4u);
    XCTAssertGreaterThan(gWalFailures, 0u);
    for (NSDictionary *state in gCommitResults) {
        XCTAssertFalse([state[@"ok"] boolValue]);
        XCTAssertEqual([state[@"code"] intValue] & 0xff, SQLITE_FULL);
        XCTAssertEqual([state[@"autocommit"] intValue], 1);
    }
    XCTAssertFalse([ClsLogStorage sharedInstance].isDbWritable);
    XCTAssertEqual([[ClsLogStorage sharedInstance] queryPendingLogs:100].count, 0u);
    XCTAssertEqual([self committedRowCount], 1u);
    [self assertNoActiveTransaction];
}

- (void)testTransientWALFullRetriesBeforeReportingSuccess {
    gWalFailuresRemaining = 1;
    XCTAssertTrue([[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[@1]]);
    XCTAssertEqual(gWalFailures, 1u);
    XCTAssertEqual(gDeleteFullHits, 2u);
    XCTAssertEqual(gCommitResults.count, 2u);
    XCTAssertEqual([gCommitResults.firstObject[@"code"] intValue] & 0xff, SQLITE_FULL);
    XCTAssertTrue([gCommitResults.lastObject[@"ok"] boolValue]);
    XCTAssertEqual([self committedRowCount], 0u);
    XCTAssertTrue([ClsLogStorage sharedInstance].isDbWritable);
    [self assertNoActiveTransaction];
}

- (void)testDeniedCommitRollsBackBeforeLaterWrite {
    gDenyCommit = YES;
    XCTAssertFalse([[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[@1]]);
    XCTAssertFalse([ClsLogStorage sharedInstance].isDbWritable);
    XCTAssertEqual(gCommitResults.count, 4u);
    for (NSDictionary *state in gCommitResults) {
        XCTAssertEqual([state[@"code"] intValue], SQLITE_AUTH);
        XCTAssertEqual([state[@"autocommit"] intValue], 0);
    }
    [self assertNoActiveTransaction];
    gDenyCommit = NO;
    Log *log = [[Log alloc] init];
    log.time = 2;
    XCTestExpectation *written = [self expectationWithDescription:@"post-failure write persisted"];
    [[ClsLogStorage sharedInstance] writeLog:log topicId:@"test-topic" completion:^(BOOL ok, NSError *error) {
        XCTAssertTrue(ok);
        XCTAssertNil(error);
        [written fulfill];
    }];
    [self waitForExpectations:@[written] timeout:3];
    XCTAssertEqual([self committedRowCount], 2u, @"write success must be visible on a separate connection");
}

- (void)testDeniedBeginDoesNotExecuteDelete {
    gDenyBegin = YES;
    XCTAssertFalse([[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[@1]]);
    XCTAssertEqual(gDeleteFullHits, 0u);
    XCTAssertEqual([self committedRowCount], 1u);
    XCTAssertFalse([ClsLogStorage sharedInstance].isDbWritable);
    [self assertNoActiveTransaction];
}

- (void)testRollbackFailureDoesNotLeaveAnActiveTransaction {
    gDenyCommit = YES;
    gDenyRollback = YES;
    XCTAssertFalse([[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[@1]]);
    XCTAssertFalse([ClsLogStorage sharedInstance].isDbWritable);
    [self assertNoActiveTransaction];
    XCTAssertEqual([self committedRowCount], 1u);
    gDenyCommit = gDenyRollback = NO;
    Log *log = [[Log alloc] init];
    log.time = 3;
    XCTestExpectation *written = [self expectationWithDescription:@"reopened database write"];
    [[ClsLogStorage sharedInstance] writeLog:log topicId:@"test-topic" completion:^(BOOL ok, NSError *error) {
        XCTAssertTrue(ok);
        XCTAssertNil(error);
        [written fulfill];
    }];
    [self waitForExpectations:@[written] timeout:3];
    XCTAssertEqual([self committedRowCount], 2u);
    [self.queue inDatabase:^(FMDatabase *db) {
        XCTAssertEqual([db intForQuery:@"PRAGMA synchronous"], 1);
        XCTAssertEqual([db longForQuery:@"PRAGMA journal_size_limit"], 4194304);
        XCTAssertEqualObjects([db stringForQuery:@"PRAGMA journal_mode"], @"wal");
    }];
    XCTAssertFalse([ClsLogStorage sharedInstance].isDbWritable);
}

- (void)testFailedCommitDoesNotResetShortDeleteCounter {
    [[ClsLogStorage sharedInstance] setValue:@2 forKey:@"consecutiveShortDeleteCount"];
    gWalFailuresRemaining = NSIntegerMax;
    XCTAssertFalse([[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[@1]]);
    XCTAssertEqual([[[ClsLogStorage sharedInstance] valueForKey:@"consecutiveShortDeleteCount"] integerValue], 2);
    XCTAssertEqual([self committedRowCount], 1u);
}

- (NSArray<NSNumber *> *)seedRowsThrough:(NSUInteger)count {
    NSMutableArray<NSNumber *> *ids = [NSMutableArray array];
    [self.queue inDatabase:^(FMDatabase *db) {
        NSString *payload = [db stringForQuery:@"SELECT log_item_data FROM cls_log_table WHERE _id=1"];
        XCTAssertNotNil(payload);
        XCTAssertTrue([db beginTransaction]);
        for (NSUInteger i = 1; i <= count; i++) {
            [ids addObject:@(i)];
            if (i == 1) continue;
            BOOL inserted = [db executeUpdate:@"INSERT INTO cls_log_table (_id, log_item_data, topic_id, create_time) VALUES (?, ?, 'test-topic', ?)"
                        withArgumentsInArray:@[@(i), payload, @(i)]];
            XCTAssertTrue(inserted);
        }
        XCTAssertTrue([db commit]);
    }];
    [gCommitResults removeAllObjects];
    return ids;
}

- (void)testBatchDeletePersistsAndPreservesUnselectedRowsAfterReopen {
    NSArray<NSNumber *> *ids = [self seedRowsThrough:250];
    ClsLogStorage *storage = [ClsLogStorage sharedInstance];
    XCTAssertTrue([storage deleteSentLogsWithIds:[ids subarrayWithRange:NSMakeRange(0, 100)]]);
    XCTAssertEqual([self committedRowCount], 150u);
    NSArray *remaining = [[storage queryPendingLogs:300] valueForKey:@"id"];
    XCTAssertEqualObjects(remaining, [ids subarrayWithRange:NSMakeRange(100, 150)]);
    [self.queue close];
    XCTAssertEqual([self committedRowCount], 150u);
    XCTAssertEqualObjects([[storage queryPendingLogs:300] valueForKey:@"id"], remaining);
    XCTAssertTrue([storage deleteSentLogsWithIds:remaining]);
    [self.queue close];
    XCTAssertEqual([self committedRowCount], 0u);
    XCTAssertEqual([storage queryPendingLogs:300].count, 0u);
    XCTAssertTrue(storage.isDbWritable);
    [self assertNoActiveTransaction];
}

- (void)testSuccessfulHTTPDrains250RowsWithoutDuplicates {
    NSArray *ids = [self seedRowsThrough:250];
    __block NSUInteger requests = 0;
    CLSSendResult *response = [[CLSSendResult alloc] init];
    response.statusCode = 200;
    response.requestID = @"normal-200";
    self.networkMock = OCMClassMock(CLSNetworkTool.class);
    OCMStub([self.networkMock isNetworkAvailable]).andReturn(YES);
    OCMStub([self.networkMock sendPostRequestSyncWithUrl:[OCMArg any] headers:[OCMArg any]
                                                  body:[OCMArg any] option:[OCMArg any]])
        .andDo(^(NSInvocation *invocation) { requests++; }).andReturn(response);
    CLSBoundedCommitSender *sender = [[CLSBoundedCommitSender alloc] init];
    sender.sentIds = [NSMutableArray array];
    [sender setConfig:[ClsLogSenderConfig configWithEndpoint:@"test.invalid"
                                               accessKeyId:@"test-id" accessKey:@"test-key"]];
    [sender sendAllPendingOnThread:NSThread.currentThread];
    XCTAssertEqual(requests, 3u);
    NSMutableArray *sizes = [NSMutableArray array];
    NSMutableArray *sent = [NSMutableArray array];
    for (NSArray *batch in sender.sentIds) {
        [sizes addObject:@(batch.count)];
        [sent addObjectsFromArray:batch];
    }
    XCTAssertEqualObjects(sizes, (@[@100, @100, @50]));
    XCTAssertEqualObjects(sent, ids);
    XCTAssertEqual([NSSet setWithArray:sent].count, 250u);
    XCTAssertEqual([self committedRowCount], 0u);
    [self.queue close];
    XCTAssertEqual([self committedRowCount], 0u);
    [sender sendAllPendingOnThread:NSThread.currentThread];
    XCTAssertEqual(requests, 3u);
    XCTAssertTrue([ClsLogStorage sharedInstance].isDbWritable);
}

- (void)testInterleavedWritesAndDeletePreservesAllNewRows {
    NSArray *ids = [self seedRowsThrough:100];
    ClsLogStorage *storage = [ClsLogStorage sharedInstance];
    XCTestExpectation *writes = [self expectationWithDescription:@"100 interleaved writes"];
    writes.expectedFulfillmentCount = 100;
    XCTestExpectation *deleted = [self expectationWithDescription:@"original batch deleted between writes"];
    dispatch_queue_t writeQueue = [storage valueForKey:@"writeQueue"];
    for (NSUInteger i = 0; i < 100; i++) {
        if (i == 50) {
            dispatch_async(writeQueue, ^{
                XCTAssertEqual([self committedRowCount], 150u);
                XCTAssertTrue([storage deleteSentLogsWithIds:ids]);
                XCTAssertEqual([self committedRowCount], 50u);
                [deleted fulfill];
            });
        }
        Log *log = [[Log alloc] init];
        log.time = (int64_t)i + 1000;
        [storage writeLog:log topicId:@"new-topic" completion:^(BOOL ok, NSError *error) {
            XCTAssertTrue(ok);
            XCTAssertNil(error);
            [writes fulfill];
        }];
    }
    [self waitForExpectations:@[writes, deleted] timeout:10];
    XCTAssertEqual([self committedRowCount], 100u);
    NSArray *remaining = [storage queryPendingLogs:200];
    XCTAssertEqual(remaining.count, 100u);
    NSSet *originalIDs = [NSSet setWithArray:ids];
    for (NSDictionary *row in remaining) XCTAssertFalse([originalIDs containsObject:row[@"id"]]);
    XCTAssertTrue([storage deleteSentLogsWithIds:[remaining valueForKey:@"id"]]);
    XCTAssertEqual([self committedRowCount], 0u);
    [self assertNoActiveTransaction];
}

- (void)testExternalWriterLockFailsSafelyWithoutDeletingRows {
    FMDatabase *writer = [FMDatabase databaseWithPath:self.path];
    XCTAssertTrue([writer open]);
    XCTAssertTrue([writer beginImmediateTransaction]);
    [self.queue inDatabase:^(FMDatabase *db) { db.maxBusyRetryTimeInterval = 0; }];
    @try {
        XCTAssertFalse([[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[@1]]);
        XCTAssertEqual(gDeleteFullHits, 0u);
        XCTAssertEqual([self committedRowCount], 1u);
        XCTAssertFalse([ClsLogStorage sharedInstance].isDbWritable);
        [self assertNoActiveTransaction];
    } @finally {
        [writer rollback];
        [writer close];
    }
}

- (void)testReadOnlyConnectionFailsSafelyWithoutDeletingRows {
    [self.queue inDatabase:^(FMDatabase *db) { XCTAssertTrue([db executeUpdate:@"PRAGMA query_only=ON"]); }];
    @try {
        XCTAssertFalse([[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[@1]]);
        XCTAssertEqual(gDeleteFullHits, 0u);
        XCTAssertEqual([self committedRowCount], 1u);
        XCTAssertFalse([ClsLogStorage sharedInstance].isDbWritable);
        [self assertNoActiveTransaction];
    } @finally {
        [self.queue inDatabase:^(FMDatabase *db) { [db executeUpdate:@"PRAGMA query_only=OFF"]; }];
    }
}

- (void)testWALIOErrorPreservesRowsAndEndsTransaction {
    gWalFailureCode = SQLITE_IOERR_WRITE;
    gWalFailuresRemaining = NSIntegerMax;
    XCTAssertFalse([[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[@1]]);
    XCTAssertGreaterThan(gWalFailures, 0u);
    XCTAssertGreaterThan(gCommitResults.count, 0u);
    for (NSDictionary *state in gCommitResults) {
        XCTAssertFalse([state[@"ok"] boolValue]);
        XCTAssertEqual([state[@"code"] intValue] & 0xff, SQLITE_IOERR);
    }
    XCTAssertFalse([ClsLogStorage sharedInstance].isDbWritable);
    XCTAssertEqual([self committedRowCount], 1u);
    [self assertNoActiveTransaction];
}

- (void)testConnectionRecoveryFailureReportsWriteFailureAndCanRetry {
    ClsLogStorage *storage = [ClsLogStorage sharedInstance];
    [storage setValue:@YES forKey:@"needsConnectionConfiguration"];
    [storage setValue:@NO forKey:@"isDbWritable"];
    gDenyConfiguration = YES;
    Log *log = [[Log alloc] init];
    log.time = 4;
    XCTestExpectation *failed = [self expectationWithDescription:@"configuration failure"];
    [storage writeLog:log topicId:@"test-topic" completion:^(BOOL ok, NSError *error) {
        XCTAssertFalse(ok);
        XCTAssertEqualObjects(error.domain, @"LogDB");
        XCTAssertEqual(error.code, -5);
        [failed fulfill];
    }];
    [self waitForExpectations:@[failed] timeout:3];
    XCTAssertEqual([self committedRowCount], 1u);
    XCTAssertTrue([[storage valueForKey:@"needsConnectionConfiguration"] boolValue]);
    gDenyConfiguration = NO;
    XCTestExpectation *written = [self expectationWithDescription:@"configuration recovered"];
    [storage writeLog:log topicId:@"test-topic" completion:^(BOOL ok, NSError *error) {
        XCTAssertTrue(ok);
        XCTAssertNil(error);
        [written fulfill];
    }];
    [self waitForExpectations:@[written] timeout:3];
    XCTAssertEqual([self committedRowCount], 2u);
    XCTAssertFalse([[storage valueForKey:@"needsConnectionConfiguration"] boolValue]);
    XCTAssertFalse(storage.isDbWritable);
    [self assertNoActiveTransaction];
}
@end
