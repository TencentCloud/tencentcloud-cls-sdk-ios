
#import <XCTest/XCTest.h>
#import <TencentCloudLogProducer/CLSNetworkUtils.h>

@interface CLSNetworkUtils (CLSTestExposed_Geo)
+ (NSDictionary *)parseGeoResponseBody:(NSString *)jsonBody usedNet:(NSString *)usedNet;
@end

@interface CLSGeoResponseTests : XCTestCase
@end

@implementation CLSGeoResponseTests

#pragma mark - 根不是 dict

- (void)testParse_RootIsArray_ReturnsEmpty {
    NSDictionary *d = nil;
    XCTAssertNoThrow(d = [CLSNetworkUtils parseGeoResponseBody:@"[]" usedNet:@"wifi"]);
    XCTAssertEqualObjects(d, @{});
}

- (void)testParse_RootIsString_ReturnsEmpty {
    NSDictionary *d = nil;
    XCTAssertNoThrow(d = [CLSNetworkUtils parseGeoResponseBody:@"\"abc\"" usedNet:@"wifi"]);
    XCTAssertEqualObjects(d, @{});
}

- (void)testParse_RootIsNull_ReturnsEmpty {
    NSDictionary *d = nil;
    XCTAssertNoThrow(d = [CLSNetworkUtils parseGeoResponseBody:@"null" usedNet:@"wifi"]);
    XCTAssertEqualObjects(d, @{});
}

- (void)testParse_RootIsNumber_ReturnsEmpty {
    NSDictionary *d = nil;
    XCTAssertNoThrow(d = [CLSNetworkUtils parseGeoResponseBody:@"123" usedNet:@"wifi"]);
    XCTAssertEqualObjects(d, @{});
}

#pragma mark - 空/非法 body

- (void)testParse_EmptyBody_ReturnsEmpty {
    XCTAssertEqualObjects([CLSNetworkUtils parseGeoResponseBody:@"" usedNet:@"wifi"], @{});
}

- (void)testParse_MalformedJson_ReturnsEmpty {
    NSDictionary *d = nil;
    XCTAssertNoThrow(d = [CLSNetworkUtils parseGeoResponseBody:@"{not json" usedNet:@"wifi"]);
    XCTAssertEqualObjects(d, @{});
}

#pragma mark - GeoInfo 字段畸形

- (void)testParse_GeoInfoIsNull_ReturnsEmpty {
    NSString *body = @"{\"GeoInfo\": null}";
    NSDictionary *d = nil;
    XCTAssertNoThrow(d = [CLSNetworkUtils parseGeoResponseBody:body usedNet:@"wifi"]);
    XCTAssertEqualObjects(d, @{});
}

- (void)testParse_GeoInfoIsString_ReturnsEmpty {
    NSString *body = @"{\"GeoInfo\": \"abc\"}";
    NSDictionary *d = nil;
    XCTAssertNoThrow(d = [CLSNetworkUtils parseGeoResponseBody:body usedNet:@"wifi"]);
    XCTAssertEqualObjects(d, @{});
}

- (void)testParse_GeoInfoIsNumber_ReturnsEmpty {
    NSString *body = @"{\"GeoInfo\": 42}";
    NSDictionary *d = nil;
    XCTAssertNoThrow(d = [CLSNetworkUtils parseGeoResponseBody:body usedNet:@"wifi"]);
    XCTAssertEqualObjects(d, @{});
}

- (void)testParse_GeoInfoIsEmptyDict_ReturnsEmpty {
    NSString *body = @"{\"GeoInfo\": {}}";
    NSDictionary *d = nil;
    XCTAssertNoThrow(d = [CLSNetworkUtils parseGeoResponseBody:body usedNet:@"wifi"]);
    XCTAssertEqualObjects(d, @{});
}

- (void)testParse_NoGeoInfoKey_ReturnsEmpty {
    NSString *body = @"{\"other\": 1}";
    NSDictionary *d = nil;
    XCTAssertNoThrow(d = [CLSNetworkUtils parseGeoResponseBody:body usedNet:@"wifi"]);
    XCTAssertEqualObjects(d, @{});
}

#pragma mark - 字段值类型异常（NSNull / NSNumber）

- (void)testParse_GeoFieldIsNull_UsesFallback {
    NSString *body = @"{\"GeoInfo\": {\"remote_addr\": null, \"provider\": \"ISP\"}}";
    NSDictionary *d = nil;
    XCTAssertNoThrow(d = [CLSNetworkUtils parseGeoResponseBody:body usedNet:@"wifi"]);
    XCTAssertNotNil(d);
    XCTAssertEqualObjects(d[@"client_ip"], @"未知",
                          @"null 字段应降级为 '未知'（不崩溃），实际 %@", d[@"client_ip"]);
    XCTAssertEqualObjects(d[@"isp_en"], @"ISP");
}

- (void)testParse_GeoFieldIsNumber_ConvertsToString {
    NSString *body = @"{\"GeoInfo\": {\"remote_addr\": 12345, \"provider\": \"ISP\"}}";
    NSDictionary *d = nil;
    XCTAssertNoThrow(d = [CLSNetworkUtils parseGeoResponseBody:body usedNet:@"wifi"]);
    XCTAssertEqualObjects(d[@"client_ip"], @"12345",
                          @"NSNumber 字段应 stringValue（不崩溃），实际 %@", d[@"client_ip"]);
}

- (void)testParse_GeoFieldIsArray_UsesFallback {
    NSString *body = @"{\"GeoInfo\": {\"remote_addr\": [1, 2]}}";
    NSDictionary *d = nil;
    XCTAssertNoThrow(d = [CLSNetworkUtils parseGeoResponseBody:body usedNet:@"wifi"]);
    XCTAssertEqualObjects(d[@"client_ip"], @"未知");
}

#pragma mark - 正常响应

- (void)testParse_Normal_AllStringFields_Success {
    NSString *body = @"{\"GeoInfo\": {"
                     @"\"remote_addr\":\"1.2.3.4\","
                     @"\"country_code\":\"CN\","
                     @"\"provider\":\"ChinaMobile\","
                     @"\"province_name\":\"GD\","
                     @"\"city_name\":\"SZ\","
                     @"\"country_name\":\"China\""
                     @"}}";
    NSDictionary *d = [CLSNetworkUtils parseGeoResponseBody:body usedNet:@"5G"];
    XCTAssertEqualObjects(d[@"client_ip"],   @"1.2.3.4");
    XCTAssertEqualObjects(d[@"country_id"],  @"CN");
    XCTAssertEqualObjects(d[@"isp_en"],      @"ChinaMobile");
    XCTAssertEqualObjects(d[@"province_en"], @"GD");
    XCTAssertEqualObjects(d[@"city_en"],     @"SZ");
    XCTAssertEqualObjects(d[@"country_en"],  @"China");
    XCTAssertEqualObjects(d[@"usedNet"],     @"5G");
    XCTAssertNotNil(d[@"defaultNet"]);
}

@end
