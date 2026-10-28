#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <TencentCloudLogProducer/ClsLogSender.h>
#import <TencentCloudLogProducer/CLSNetworkTool.h>
#import <TencentCloudLogProducer/ClsLogs.pbobjc.h>

@interface LogSender (TestExposed)
- (BOOL)sendLogsGroup:(NSArray<NSDictionary *> *)groupLogs forTopic:(NSString *)topicID;
@end

@interface CLSTestRequestCapture : NSObject
@property (class, nonatomic, copy, nullable) NSString *lastUrl;
@property (class, nonatomic, copy, nullable) NSDictionary *lastHeaders;
@property (class, nonatomic, copy, nullable) NSData *lastBody;
@property (class, nonatomic, assign) NSInteger mockStatusCode;
+ (void)reset;
@end

@implementation CLSTestRequestCapture

static NSString *_lastUrl;
static NSDictionary *_lastHeaders;
static NSData *_lastBody;
static NSInteger _mockStatusCode = 200;

+ (NSString *)lastUrl { return _lastUrl; }
+ (void)setLastUrl:(NSString *)v { _lastUrl = [v copy]; }
+ (NSDictionary *)lastHeaders { return _lastHeaders; }
+ (void)setLastHeaders:(NSDictionary *)v { _lastHeaders = [v copy]; }
+ (NSData *)lastBody { return _lastBody; }
+ (void)setLastBody:(NSData *)v { _lastBody = [v copy]; }
+ (NSInteger)mockStatusCode { return _mockStatusCode; }
+ (void)setMockStatusCode:(NSInteger)v { _mockStatusCode = v; }

+ (void)reset {
    _lastUrl = nil;
    _lastHeaders = nil;
    _lastBody = nil;
    _mockStatusCode = 200;
}
@end

@implementation CLSNetworkTool (CLSWeakAuthMock)

+ (CLSSendResult *)mock_sendPostRequestSyncWithUrl:(NSString *)url
                                           headers:(NSDictionary *)headers
                                              body:(NSData *)body
                                            option:(ClsPostOption *)option {
    CLSTestRequestCapture.lastUrl = url;
    CLSTestRequestCapture.lastHeaders = headers;
    CLSTestRequestCapture.lastBody = body;

    CLSSendResult *result = [[CLSSendResult alloc] init];
    result.statusCode = CLSTestRequestCapture.mockStatusCode;
    result.requestID = @"mock-cls-req-id-xxxx";
    result.message = CLSTestRequestCapture.mockStatusCode == 200
        ? @"{\"errorcode\":\"\",\"errormessage\":\"\"}"
        : @"{\"errorcode\":\"AuthFailure.UnauthorizedOperation\",\"errormessage\":\"invalid uin\"}";
    return result;
}

@end

static Log *CLSMakeFakeLog(void) {
    Log *log = [[Log alloc] init];
    Log_Content *c = [[Log_Content alloc] init];
    c.key = @"level";
    c.value = @"INFO";
    [log.contentsArray addObject:c];
    log.time = (long long)[[NSDate date] timeIntervalSince1970];
    return log;
}

static NSDictionary *CLSMakeFakeLogEntry(NSString *topicId, NSNumber *logId) {
    return @{@"log_item": CLSMakeFakeLog(),
             @"id": logId,
             @"topic_id": topicId};
}

@interface CLSWeakAuthSenderTests : XCTestCase
@end

@implementation CLSWeakAuthSenderTests

+ (void)setUp {
    [super setUp];
    Method original = class_getClassMethod([CLSNetworkTool class],
                                           @selector(sendPostRequestSyncWithUrl:headers:body:option:));
    Method mock = class_getClassMethod([CLSNetworkTool class],
                                       @selector(mock_sendPostRequestSyncWithUrl:headers:body:option:));
    if (original && mock) {
        method_exchangeImplementations(original, mock);
    }
}

- (void)setUp {
    [super setUp];
    [CLSTestRequestCapture reset];
}

- (void)testCase01_StrongAuth_FullAKSK_NoUin {
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou.cls.tencentcs.com"
                                                            accessKeyId:@"AKID_test"
                                                              accessKey:@"KEY_test"];
    XCTAssertFalse([LogSender isWeakAuthConfig:config]);
}

- (void)testCase02_StrongAuth_FullAKSK_WithUin_IgnoresUin {
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou.cls.tencentcs.com"
                                                            accessKeyId:@"AKID_test"
                                                              accessKey:@"KEY_test"];
    config.uin = @"1000011275789";
    XCTAssertFalse([LogSender isWeakAuthConfig:config]);
}

- (void)testCase03_WeakAuth_EmptyAK_ValidUin {
    ClsLogSenderConfig *config = [[ClsLogSenderConfig alloc] init];
    config.endpoint = @"ap-guangzhou.cls.tencentcs.com";
    config.accessKeyId = @"";
    config.accessKey = @"KEY_test";
    config.uin = @"1000011275789";
    XCTAssertTrue([LogSender isWeakAuthConfig:config]);
    XCTAssertTrue([LogSender isUinValid:config.uin]);
}

- (void)testCase04_WeakAuth_EmptySK_ValidUin_ORSemantic {
    ClsLogSenderConfig *config = [[ClsLogSenderConfig alloc] init];
    config.endpoint = @"ap-guangzhou.cls.tencentcs.com";
    config.accessKeyId = @"AKID_test";
    config.accessKey = @"";
    config.uin = @"1000011275789";
    XCTAssertTrue([LogSender isWeakAuthConfig:config]);
}

- (void)testCase05_InvalidConfig_NoCredentials {
    ClsLogSenderConfig *config = [[ClsLogSenderConfig alloc] init];
    config.endpoint = @"ap-guangzhou.cls.tencentcs.com";
    config.accessKeyId = @"";
    config.accessKey = @"";
    XCTAssertTrue([LogSender isWeakAuthConfig:config]);
    XCTAssertFalse([LogSender isUinValid:config.uin]);
}

- (void)testCase06_InvalidConfig_NonNumericUin {
    NSArray<NSString *> *invalidUins = @[
        @"abc",
        @"-100",
        @"100 200",
        @"100.5",
        @"",
        @"100000a",
        @"\u4e00",
    ];
    for (NSString *badUin in invalidUins) {
        XCTAssertFalse([LogSender isUinValid:badUin], @"'%@' should be invalid", badUin);
    }
    XCTAssertTrue([LogSender isUinValid:@"1000011275789"]);
    XCTAssertTrue([LogSender isUinValid:@"0"]);
    XCTAssertTrue([LogSender isUinValid:@"1"]);
}

- (void)testCase07_WeakAuthCandidate_OnlySecretID_NoUin {
    ClsLogSenderConfig *config = [[ClsLogSenderConfig alloc] init];
    config.endpoint = @"ap-guangzhou.cls.tencentcs.com";
    config.accessKeyId = @"AKID_test";
    config.accessKey = @"";
    XCTAssertTrue([LogSender isWeakAuthConfig:config]);
    XCTAssertFalse([LogSender isUinValid:config.uin]);
}

- (void)testCase08_WeakAuth_RequestHeadersAndUrl {
    ClsLogSenderConfig *config = [[ClsLogSenderConfig alloc] init];
    config.endpoint = @"ap-guangzhou.cls.tencentcs.com";
    config.accessKeyId = @"";
    config.accessKey = @"";
    config.uin = @"1000011275789";

    LogSender *sender = [LogSender sharedSender];
    [sender setConfig:config];

    NSArray *entries = @[CLSMakeFakeLogEntry(@"topic-xyz", @1)];
    [sender sendLogsGroup:entries forTopic:@"topic-xyz"];

    NSDictionary *h = CLSTestRequestCapture.lastHeaders;
    XCTAssertNotNil(h);

    XCTAssertEqualObjects(h[@"x-cls-auth-mode"], @"weak");
    XCTAssertEqualObjects(h[@"X-CLS-Uin"], @"1000011275789");

    XCTAssertNil(h[@"Authorization"]);
    XCTAssertNil(h[@"X-Cls-Token"]);

    XCTAssertEqualObjects(h[@"Content-Type"], @"application/x-protobuf");
    XCTAssertEqualObjects(h[@"User-Agent"], @"tencent-log-sdk-ios v3.3.1");
    XCTAssertEqualObjects(h[@"x-cls-compress-type"], @"lz4");

    XCTAssertTrue([CLSTestRequestCapture.lastUrl
                   hasPrefix:@"https://ap-guangzhou.cls.tencentcs.com/structuredlog?"]);
    XCTAssertTrue([CLSTestRequestCapture.lastUrl containsString:@"topic_id=topic-xyz"]);

    XCTAssertGreaterThan(CLSTestRequestCapture.lastBody.length, 0u);
}

- (void)testCase09_UpdateToken_NoOpUnderWeakAuth {
    ClsLogSenderConfig *config = [[ClsLogSenderConfig alloc] init];
    config.endpoint = @"ap-guangzhou.cls.tencentcs.com";
    config.accessKeyId = @"";
    config.accessKey = @"";
    config.uin = @"1000011275789";

    LogSender *sender = [LogSender sharedSender];
    [sender setConfig:config];
    [sender updateToken:@"SOME_STS_TOKEN_THAT_SHOULD_BE_IGNORED"];

    NSArray *entries = @[CLSMakeFakeLogEntry(@"t", @2)];
    [sender sendLogsGroup:entries forTopic:@"t"];

    NSDictionary *h = CLSTestRequestCapture.lastHeaders;
    XCTAssertEqualObjects(h[@"x-cls-auth-mode"], @"weak");
    XCTAssertNil(h[@"X-Cls-Token"]);
    XCTAssertNil(h[@"Authorization"]);
}

- (void)testCase10_StrongAuth_RequestHeaders_And_401_Parsing {
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou.cls.tencentcs.com"
                                                            accessKeyId:@"AKID_strong"
                                                              accessKey:@"KEY_strong"];
    LogSender *sender = [LogSender sharedSender];
    [sender setConfig:config];

    CLSTestRequestCapture.mockStatusCode = 200;
    NSArray *entries = @[CLSMakeFakeLogEntry(@"t", @3)];
    [sender sendLogsGroup:entries forTopic:@"t"];

    NSDictionary *h = CLSTestRequestCapture.lastHeaders;
    XCTAssertNotNil(h[@"Authorization"]);
    XCTAssertTrue([h[@"Authorization"] hasPrefix:@"q-sign-algorithm=sha1"]);
    XCTAssertNil(h[@"x-cls-auth-mode"]);
    XCTAssertNil(h[@"X-CLS-Uin"]);

    CLSTestRequestCapture.mockStatusCode = 401;
    NSArray *entries2 = @[CLSMakeFakeLogEntry(@"t", @4)];
    BOOL ok = [sender sendLogsGroup:entries2 forTopic:@"t"];
    XCTAssertFalse(ok);
}

- (void)testCase11_CopyWithZone_IncludesUin {
    ClsLogSenderConfig *config = [[ClsLogSenderConfig alloc] init];
    config.endpoint = @"ap-guangzhou.cls.tencentcs.com";
    config.accessKeyId = @"";
    config.accessKey = @"";
    config.uin = @"1000011275789";
    config.token = @"some-token";

    ClsLogSenderConfig *copy = [config copy];

    XCTAssertEqualObjects(copy.endpoint, config.endpoint);
    XCTAssertEqualObjects(copy.accessKeyId, config.accessKeyId);
    XCTAssertEqualObjects(copy.accessKey, config.accessKey);
    XCTAssertEqualObjects(copy.token, config.token);
    XCTAssertEqualObjects(copy.uin, @"1000011275789");
    XCTAssertNotEqual(copy, config);
}

@end
