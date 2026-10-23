
#import <XCTest/XCTest.h>
#import <TencentCloudLogProducer/ClsLogStorage.h>
#import <TencentCloudLogProducer/ClsLogs.pbobjc.h>

@interface CLSStorageRoundCTests : XCTestCase
@end

@implementation CLSStorageRoundCTests

+ (Log *)buildLogWithPayloadBytes:(NSUInteger)payload {
    Log *log = [[Log alloc] init];
    log.time = (int64_t)([[NSDate date] timeIntervalSince1970]);
    Log_Content *c = [[Log_Content alloc] init];
    c.key = @"k";
    NSMutableString *big = [NSMutableString stringWithCapacity:payload];
    for (NSUInteger i = 0; i < payload; i++) {
        [big appendString:@"a"];
    }
    c.value = big;
    [log.contentsArray addObject:c];
    return log;
}

#pragma mark - #14

- (void)testWriteLog_ExceedsLimit_FailsWithCode_minus4 {
    Log *huge = [CLSStorageRoundCTests buildLogWithPayloadBytes:600 * 1024];
    XCTestExpectation *exp = [self expectationWithDescription:@"completion called"];
    __block BOOL ok = YES;
    __block NSError *err = nil;
    [[ClsLogStorage sharedInstance] writeLog:huge topicId:@"t_oversized_test" completion:^(BOOL success, NSError * _Nullable error) {
        ok = success;
        err = error;
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:3.0 handler:nil];

    XCTAssertFalse(ok, @"oversized log should NOT succeed at writeLog layer");
    XCTAssertNotNil(err);
    XCTAssertEqual(err.code, -4, @"error code should be -4 (exceeds size limit)");
}

- (void)testWriteLog_NormalSize_Succeeds {
    Log *small = [CLSStorageRoundCTests buildLogWithPayloadBytes:500];
    XCTestExpectation *exp = [self expectationWithDescription:@"completion called"];
    __block BOOL ok = NO;
    [[ClsLogStorage sharedInstance] writeLog:small topicId:@"t_normal_test" completion:^(BOOL success, NSError * _Nullable error) {
        ok = success;
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:3.0 handler:nil];
    XCTAssertTrue(ok, @"small log should succeed");
}

#pragma mark - sanity

- (void)testWriteLog_SmallLog_Idempotent {
    for (int i = 0; i < 3; i++) {
        Log *l = [CLSStorageRoundCTests buildLogWithPayloadBytes:200];
        XCTestExpectation *exp = [self expectationWithDescription:[NSString stringWithFormat:@"w%d", i]];
        __block BOOL ok = NO;
        [[ClsLogStorage sharedInstance] writeLog:l topicId:@"t_c1_smoke" completion:^(BOOL s, NSError *e) {
            ok = s;
            [exp fulfill];
        }];
        [self waitForExpectationsWithTimeout:2.0 handler:nil];
        XCTAssertTrue(ok, @"small log iteration %d should succeed", i);
    }
}

@end
