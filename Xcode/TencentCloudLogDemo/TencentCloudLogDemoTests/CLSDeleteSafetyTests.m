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

@end
