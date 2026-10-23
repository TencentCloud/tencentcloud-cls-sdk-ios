
#import <XCTest/XCTest.h>
#import <TencentCloudLogProducer/CLSNetworkUtils.h>

@interface CLSNetTokenParseTests : XCTestCase
@end

@implementation CLSNetTokenParseTests

+ (NSString *)tokenFromJSONString:(NSString *)json {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    return [data base64EncodedStringWithOptions:0];
}

#pragma mark - 入参边界

- (void)testParseNetToken_NilInput_ReturnsEmpty {
    NSDictionary *r = [CLSNetworkUtils parseNetToken:nil];
    XCTAssertEqualObjects(r, @{});
}

- (void)testParseNetToken_EmptyInput_ReturnsEmpty {
    XCTAssertEqualObjects([CLSNetworkUtils parseNetToken:@""], @{});
}

- (void)testParseNetToken_InvalidBase64_ReturnsEmpty {
    NSString *token = [CLSNetTokenParseTests tokenFromJSONString:@"not-a-json-at-all"];
    NSDictionary *r = [CLSNetworkUtils parseNetToken:token];
    XCTAssertEqualObjects(r, @{});
}

#pragma mark - JSON 类型异常（修复的核心场景）

- (void)testParseNetToken_RootIsArray_DoesNotCrash_ReturnsEmpty {
    NSString *token = [CLSNetTokenParseTests tokenFromJSONString:@"[1,2,3]"];
    NSDictionary *r = [CLSNetworkUtils parseNetToken:token];
    XCTAssertEqualObjects(r, @{});
}

- (void)testParseNetToken_RootIsString_DoesNotCrash_ReturnsEmpty {
    NSString *token = [CLSNetTokenParseTests tokenFromJSONString:@"\"hello\""];
    NSDictionary *r = [CLSNetworkUtils parseNetToken:token];
    XCTAssertEqualObjects(r, @{});
}

- (void)testParseNetToken_FieldIsNull_DoesNotCrash_ReturnsEmpty {
    NSString *json = @"{\"n_a_id\":null,\"key\":\"k\",\"uin\":\"1\",\"region\":\"r\",\"topic_id\":\"t\"}";
    NSString *token = [CLSNetTokenParseTests tokenFromJSONString:json];
    NSDictionary *r = [CLSNetworkUtils parseNetToken:token];
    XCTAssertEqualObjects(r, @{}, @"n_a_id=null 应被判为空字段而非崩溃");
}

- (void)testParseNetToken_NAIDIsNumber_DoesNotCrash_ParsesSuccessfully {
    NSString *json = @"{\"n_a_id\":12345,\"key\":\"k\",\"uin\":1,\"region\":\"r\",\"topic_id\":\"t\"}";
    NSString *token = [CLSNetTokenParseTests tokenFromJSONString:json];
    NSDictionary *r = [CLSNetworkUtils parseNetToken:token];
    XCTAssertEqualObjects(r[@"networkAppId"], @"12345");
    XCTAssertEqualObjects(r[@"appKey"], @"k");
    XCTAssertEqualObjects(r[@"uin"], @"1");
}

- (void)testParseNetToken_UinIsNumber_RegressesToString {
    NSString *json = @"{\"n_a_id\":\"nid\",\"key\":\"k\",\"uin\":100001,\"region\":\"r\",\"topic_id\":\"t\"}";
    NSString *token = [CLSNetTokenParseTests tokenFromJSONString:json];
    NSDictionary *r = [CLSNetworkUtils parseNetToken:token];
    XCTAssertEqualObjects(r[@"uin"], @"100001");
}

- (void)testParseNetToken_AllFieldsAreNull_DoesNotCrash_ReturnsEmpty {
    NSString *json = @"{\"n_a_id\":null,\"key\":null,\"uin\":null,\"region\":null,\"topic_id\":null}";
    NSString *token = [CLSNetTokenParseTests tokenFromJSONString:json];
    NSDictionary *r = [CLSNetworkUtils parseNetToken:token];
    XCTAssertEqualObjects(r, @{});
}

- (void)testParseNetToken_FieldIsNestedObject_DoesNotCrash_ReturnsEmpty {
    NSString *json = @"{\"n_a_id\":{\"x\":1},\"key\":[1,2],\"uin\":\"1\",\"region\":\"r\",\"topic_id\":\"t\"}";
    NSString *token = [CLSNetTokenParseTests tokenFromJSONString:json];
    NSDictionary *r = [CLSNetworkUtils parseNetToken:token];
    XCTAssertEqualObjects(r, @{}, @"嵌套对象/数组字段应被视为空而非崩溃");
}

#pragma mark - 正常路径（基线）

- (void)testParseNetToken_AllStringFields_ParsesSuccessfully {
    NSString *json = @"{\"n_a_id\":\"nid\",\"key\":\"abcdef\",\"uin\":\"u1\",\"region\":\"ap-guangzhou\",\"topic_id\":\"tid-1\"}";
    NSString *token = [CLSNetTokenParseTests tokenFromJSONString:json];
    NSDictionary *r = [CLSNetworkUtils parseNetToken:token];
    XCTAssertEqualObjects(r[@"networkAppId"], @"nid");
    XCTAssertEqualObjects(r[@"appKey"], @"abcdef");
    XCTAssertEqualObjects(r[@"uin"], @"u1");
    XCTAssertEqualObjects(r[@"region"], @"ap-guangzhou");
    XCTAssertEqualObjects(r[@"topic_id"], @"tid-1");
}

- (void)testParseNetToken_URLSafeBase64_IsDecodedCorrectly {
    NSString *json = @"{\"n_a_id\":\"nid\",\"key\":\"k+/\",\"uin\":\"1\",\"region\":\"r\",\"topic_id\":\"t\"}";
    NSString *rawBase64 = [CLSNetTokenParseTests tokenFromJSONString:json];
    NSString *urlSafe = [[rawBase64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
                                     stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    urlSafe = [urlSafe stringByReplacingOccurrencesOfString:@"=" withString:@""];
    NSDictionary *r = [CLSNetworkUtils parseNetToken:urlSafe];
    XCTAssertEqualObjects(r[@"appKey"], @"k+/");
}

@end
