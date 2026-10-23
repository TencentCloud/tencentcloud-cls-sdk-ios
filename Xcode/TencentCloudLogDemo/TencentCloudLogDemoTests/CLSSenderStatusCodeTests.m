//
//  CLSSenderStatusCodeTests.m
//  TencentCloudLogDemoTests
//
//  专项验证 ClsLogSender.m `handleSendResult:` 的三分支分类：
//    - 保留（keep）：
//        (a) isNetworkError:   statusCode < 0
//        (b) isTransientServerError: 5xx / 429 / 408 / 403
//        (c) isOutsideHttpRange:  正数但 <100 或 >599（R-6 的产线风险所在）
//    - 删除（delete）：
//        4xx 中除去 429/408/403 的其它永久错误（例：400 / 401 / 404 / 413）
//
//  走通产码：
//    sendLogsGroup → CLSNetworkTool.sendPostRequestSyncWithUrl（已被 mock）
//      → handleSendResult → 若 shouldKeepLogs=NO 则调用 deleteSentLogsWithIds
//
//  检测方式：
//    swizzle `-[ClsLogStorage deleteSentLogsWithIds:]` 捕获调用参数，
//    精确判断"是否删除了 logIds"。
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <TencentCloudLogProducer/ClsLogSender.h>
#import <TencentCloudLogProducer/ClsLogStorage.h>
#import <TencentCloudLogProducer/CLSNetworkTool.h>
#import <TencentCloudLogProducer/ClsLogs.pbobjc.h>
#import "CLSTestCredentials.h"

@interface LogSender (TestExposed)
- (BOOL)sendLogsGroup:(NSArray<NSDictionary *> *)groupLogs forTopic:(NSString *)topicID;
@end

#pragma mark - 复用 CLSWeakAuthSenderTests 的网络 mock，并捕获 Storage.delete 调用

@interface CLSSenderStatusCaptureStore : NSObject
@property (class, nonatomic, assign) NSInteger mockStatusCode;
@property (class, nonatomic, strong, nullable) NSArray<NSNumber *> *lastDeletedIds;
@property (class, nonatomic, assign) NSInteger deleteCallCount;
+ (void)reset;
@end
@implementation CLSSenderStatusCaptureStore
static NSInteger _storeMockStatus = 200;
static NSArray<NSNumber *> *_storeLastDeletedIds;
static NSInteger _storeDeleteCount = 0;
+ (NSInteger)mockStatusCode { return _storeMockStatus; }
+ (void)setMockStatusCode:(NSInteger)v { _storeMockStatus = v; }
+ (NSArray *)lastDeletedIds { return _storeLastDeletedIds; }
+ (void)setLastDeletedIds:(NSArray *)v { _storeLastDeletedIds = [v copy]; }
+ (NSInteger)deleteCallCount { return _storeDeleteCount; }
+ (void)setDeleteCallCount:(NSInteger)v { _storeDeleteCount = v; }
+ (void)reset {
    _storeMockStatus = 200;
    _storeLastDeletedIds = nil;
    _storeDeleteCount = 0;
}
@end

#pragma mark - mock CLSNetworkTool（独立 selector，避免和 CLSWeakAuthSenderTests 冲突）

@implementation CLSNetworkTool (SenderStatusMock)

+ (CLSSendResult *)mock_statustest_sendPostRequestSyncWithUrl:(NSString *)url
                                                       headers:(NSDictionary *)headers
                                                          body:(NSData *)body
                                                        option:(ClsPostOption *)option {
    CLSSendResult *result = [[CLSSendResult alloc] init];
    result.statusCode = CLSSenderStatusCaptureStore.mockStatusCode;
    result.requestID = @"mock-cls-req-status";
    result.message = @"mock";
    return result;
}

@end

#pragma mark - mock ClsLogStorage.deleteSentLogsWithIds:

@implementation ClsLogStorage (SenderStatusMock)

- (BOOL)mock_statustest_deleteSentLogsWithIds:(NSArray<NSNumber *> *)logIds {
    CLSSenderStatusCaptureStore.lastDeletedIds = logIds;
    CLSSenderStatusCaptureStore.deleteCallCount = CLSSenderStatusCaptureStore.deleteCallCount + 1;
    return YES;  // 不实际走 DB
}

@end

#pragma mark - helpers

static Log *CLSSStat_MakeFakeLog(void) {
    Log *log = [[Log alloc] init];
    Log_Content *c = [[Log_Content alloc] init];
    c.key = @"message"; c.value = @"status-code-branch-test";
    [log.contentsArray addObject:c];
    log.time = (long long)[[NSDate date] timeIntervalSince1970];
    return log;
}
static NSDictionary *CLSSStat_MakeEntry(NSString *topicId, NSNumber *logId) {
    return @{@"log_item": CLSSStat_MakeFakeLog(),
             @"id": logId,
             @"topic_id": topicId};
}

@interface CLSSenderStatusCodeTests : XCTestCase
@end

@implementation CLSSenderStatusCodeTests

+ (void)setUp {
    [super setUp];
    // swizzle 网络发送
    Method origNet = class_getClassMethod([CLSNetworkTool class],
                                          @selector(sendPostRequestSyncWithUrl:headers:body:option:));
    Method mockNet = class_getClassMethod([CLSNetworkTool class],
                                          @selector(mock_statustest_sendPostRequestSyncWithUrl:headers:body:option:));
    if (origNet && mockNet) method_exchangeImplementations(origNet, mockNet);

    // swizzle Storage.delete
    Method origDel = class_getInstanceMethod([ClsLogStorage class],
                                             @selector(deleteSentLogsWithIds:));
    Method mockDel = class_getInstanceMethod([ClsLogStorage class],
                                             @selector(mock_statustest_deleteSentLogsWithIds:));
    if (origDel && mockDel) method_exchangeImplementations(origDel, mockDel);
}

+ (void)tearDown {
    // 还原
    Method origNet = class_getClassMethod([CLSNetworkTool class],
                                          @selector(sendPostRequestSyncWithUrl:headers:body:option:));
    Method mockNet = class_getClassMethod([CLSNetworkTool class],
                                          @selector(mock_statustest_sendPostRequestSyncWithUrl:headers:body:option:));
    if (origNet && mockNet) method_exchangeImplementations(origNet, mockNet);

    Method origDel = class_getInstanceMethod([ClsLogStorage class],
                                             @selector(deleteSentLogsWithIds:));
    Method mockDel = class_getInstanceMethod([ClsLogStorage class],
                                             @selector(mock_statustest_deleteSentLogsWithIds:));
    if (origDel && mockDel) method_exchangeImplementations(origDel, mockDel);
    [super tearDown];
}

- (void)setUp {
    [super setUp];
    [CLSSenderStatusCaptureStore reset];
    ClsLogSenderConfig *cfg = [ClsLogSenderConfig configWithEndpoint:kCLSTestEndpoint
                                                         accessKeyId:kCLSTestSecretId
                                                           accessKey:kCLSTestSecretKey];
    [[LogSender sharedSender] setConfig:cfg];
}

- (void)runStatus:(NSInteger)status expectKeep:(BOOL)expectKeep label:(NSString *)label {
    CLSSenderStatusCaptureStore.mockStatusCode = status;
    NSArray *entries = @[CLSSStat_MakeEntry(@"status-branch", @(status + 10000))];
    (void)[[LogSender sharedSender] sendLogsGroup:entries forTopic:@"status-branch"];

    if (expectKeep) {
        XCTAssertEqual(CLSSenderStatusCaptureStore.deleteCallCount, 0,
                       @"[%@] status=%ld 应保留日志，但 Storage.delete 被调用了 %ld 次",
                       label, (long)status, (long)CLSSenderStatusCaptureStore.deleteCallCount);
    } else {
        XCTAssertEqual(CLSSenderStatusCaptureStore.deleteCallCount, 1,
                       @"[%@] status=%ld 应永久删除日志，但 Storage.delete 调用次数=%ld",
                       label, (long)status, (long)CLSSenderStatusCaptureStore.deleteCallCount);
    }
}

#pragma mark - 分支 A：isNetworkError (status < 0) → 保留

- (void)test_handleSendResult_A1_networkError_minus1_keeps {
    [self runStatus:-1 expectKeep:YES label:@"A1 -1 (R-6 映射)"];
}
- (void)test_handleSendResult_A2_networkError_NSURLErrorTimedOut_keeps {
    [self runStatus:-1001 expectKeep:YES label:@"A2 NSURLErrorTimedOut"];
}
- (void)test_handleSendResult_A3_networkError_NSURLErrorCannotFindHost_keeps {
    [self runStatus:-1003 expectKeep:YES label:@"A3 NSURLErrorCannotFindHost"];
}

#pragma mark - 分支 B：isTransientServerError → 保留

- (void)test_handleSendResult_B1_server500_keeps {
    [self runStatus:500 expectKeep:YES label:@"B1 500"];
}
- (void)test_handleSendResult_B2_server503_keeps {
    [self runStatus:503 expectKeep:YES label:@"B2 503"];
}
- (void)test_handleSendResult_B3_server599_keeps {
    [self runStatus:599 expectKeep:YES label:@"B3 599（5xx 上界）"];
}
- (void)test_handleSendResult_B4_rate_limit_429_keeps {
    [self runStatus:429 expectKeep:YES label:@"B4 429 TooManyRequests"];
}
- (void)test_handleSendResult_B5_request_timeout_408_keeps {
    [self runStatus:408 expectKeep:YES label:@"B5 408 RequestTimeout"];
}
- (void)test_handleSendResult_B6_forbidden_403_keeps {
    [self runStatus:403 expectKeep:YES label:@"B6 403 Forbidden (SDK 允许重试)"];
}

#pragma mark - 分支 C：isOutsideHttpRange (0<status<100 or status>599) → 保留
//   核心：R-6 的产线风险即在此；若有人收窄这个条件，
//   未来 CFNetwork 自定义正码（如 601、78）会被误删

- (void)test_handleSendResult_C1_lowerThan_100_keeps {
    [self runStatus:78 expectKeep:YES label:@"C1 正数 <100（如旧 CFNetwork 码）"];
}
- (void)test_handleSendResult_C2_higherThan_599_keeps {
    [self runStatus:601 expectKeep:YES label:@"C2 正数 >599"];
}
- (void)test_handleSendResult_C3_very_high_keeps {
    [self runStatus:9999 expectKeep:YES label:@"C3 正数 9999（极端值）"];
}

#pragma mark - 分支 D：永久失败 → 删除

- (void)test_handleSendResult_D1_badRequest_400_deletes {
    [self runStatus:400 expectKeep:NO label:@"D1 400 BadRequest"];
}
- (void)test_handleSendResult_D2_unauthorized_401_deletes {
    [self runStatus:401 expectKeep:NO label:@"D2 401 Unauthorized"];
}
- (void)test_handleSendResult_D3_notFound_404_deletes {
    [self runStatus:404 expectKeep:NO label:@"D3 404 NotFound"];
}
- (void)test_handleSendResult_D4_payloadTooLarge_413_deletes {
    [self runStatus:413 expectKeep:NO label:@"D4 413 PayloadTooLarge"];
}

#pragma mark - 边界：200 OK → 成功后调用 delete 清理已发日志（不同于永久失败删除）

- (void)test_handleSendResult_E1_ok_200_deletes_as_success_cleanup {
    // 200 的 delete 是"成功后清理"，和永久失败的 delete 语义不同
    // 产码路径：result.statusCode == 200 → deleteSentLogsWithIds → return YES
    // 验证：delete 必须被调用，且日志 id 正确传入
    CLSSenderStatusCaptureStore.mockStatusCode = 200;
    NSArray *entries = @[CLSSStat_MakeEntry(@"status-branch", @20042)];
    BOOL ok = [[LogSender sharedSender] sendLogsGroup:entries forTopic:@"status-branch"];

    XCTAssertTrue(ok, @"E1 200 成功，sendLogsGroup 应返回 YES");
    XCTAssertEqual(CLSSenderStatusCaptureStore.deleteCallCount, 1,
                   @"E1 200 应调用 Storage.delete 清理已发日志，实际调用=%ld",
                   (long)CLSSenderStatusCaptureStore.deleteCallCount);
    XCTAssertEqualObjects(CLSSenderStatusCaptureStore.lastDeletedIds, @[@20042],
                          @"E1 200 清理的 id 列表必须与发送的一致");
}

@end
