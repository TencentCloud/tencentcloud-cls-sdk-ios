
#import <XCTest/XCTest.h>
#import <TencentCloudLogProducer/ClsLogSender.h>
#import <TencentCloudLogProducer/ClsLogModel.h>

@interface CLSLogSwitchTests : XCTestCase
@end

@implementation CLSLogSwitchTests

- (void)setUp {
    [super setUp];
    [LogSender setLogEnabled:NO];
}

- (void)tearDown {
    [LogSender setLogEnabled:NO];
    [super tearDown];
}

#pragma mark - 开关 API 基础行为

- (void)testLogSwitchDefaultsToDisabled {
    XCTAssertFalse(CLSLogIsEnabled(),
                   @"SDK 日志开关默认应为关闭");
}

- (void)testLogSwitchCanBeEnabledAndDisabled {
    [LogSender setLogEnabled:YES];
    XCTAssertTrue(CLSLogIsEnabled(), @"setLogEnabled:YES 后开关应为开启");

    [LogSender setLogEnabled:NO];
    XCTAssertFalse(CLSLogIsEnabled(), @"setLogEnabled:NO 后开关应为关闭");
}

- (void)testLogSwitchIsIdempotent {
    [LogSender setLogEnabled:YES];
    [LogSender setLogEnabled:YES];
    [LogSender setLogEnabled:YES];
    XCTAssertTrue(CLSLogIsEnabled());

    [LogSender setLogEnabled:NO];
    [LogSender setLogEnabled:NO];
    XCTAssertFalse(CLSLogIsEnabled());
}

#pragma mark - 宏体短路：开关关闭时参数不求值

- (void)testCLSLogDoesNotEvaluateArgumentsWhenDisabled {
    __block NSInteger sideEffectCount = 0;
    NSString *(^trackingDesc)(void) = ^NSString *{
        sideEffectCount++;
        return @"should-not-be-evaluated";
    };

    [LogSender setLogEnabled:NO];
    for (int i = 0; i < 10; i++) {
        CLSLog(@"test disabled: %@", trackingDesc());
    }
    XCTAssertEqual(sideEffectCount, 0,
                   @"开关关闭时 CLSLog 参数应整体短路，不求值");
}

- (void)testCLSLogEvaluatesArgumentsWhenEnabled {
    __block NSInteger sideEffectCount = 0;
    NSString *(^trackingDesc)(void) = ^NSString *{
        sideEffectCount++;
        return @"evaluated";
    };

    [LogSender setLogEnabled:YES];
    for (int i = 0; i < 5; i++) {
        CLSLog(@"test enabled: %@", trackingDesc());
    }
    XCTAssertEqual(sideEffectCount, 5,
                   @"开关开启时 CLSLog 参数应被求值");
}

#pragma mark - CLSMask 掩码行为

- (void)testCLSMaskHandlesNil {
    XCTAssertEqualObjects(CLSMask(nil), @"(nil)");
}

- (void)testCLSMaskHandlesEmptyString {
    XCTAssertEqualObjects(CLSMask(@""), @"(nil)");
}

- (void)testCLSMaskForShortStringsIsFullyMasked {
    XCTAssertEqualObjects(CLSMask(@"a"), @"***(len=1)");
    XCTAssertEqualObjects(CLSMask(@"ab"), @"***(len=2)");
    XCTAssertEqualObjects(CLSMask(@"abcd"), @"***(len=4)");
}

- (void)testCLSMaskForLongStringsKeepsPrefixAndSuffix {
    XCTAssertEqualObjects(CLSMask(@"abcde"), @"ab***de(len=5)");
    XCTAssertEqualObjects(CLSMask(@"100012345678901234"),
                          @"10***34(len=18)");
}

- (void)testCLSMaskDoesNotLeakSensitiveMiddleContent {
    NSString *secret = @"1234567890ABCDEF";
    NSString *masked = CLSMask(secret);
    XCTAssertFalse([masked containsString:@"34567890ABCD"],
                   @"掩码结果不应泄漏原串中间部分");
}

@end
