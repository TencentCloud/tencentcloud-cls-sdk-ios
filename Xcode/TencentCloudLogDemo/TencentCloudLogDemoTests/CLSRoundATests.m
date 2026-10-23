
#import <XCTest/XCTest.h>
#import <TencentCloudLogProducer/CLSUserInfo.h>

@interface CLSRoundATests : XCTestCase
@end

@implementation CLSRoundATests

- (void)testUserInfoCopy_ThenAddExt_DoesNotCrash {
    CLSUserInfo *orig = [CLSUserInfo userInfo];
    orig.uid = @"u1";
    orig.channel = @"c1";
    [orig addExt:@"vA" key:@"kA"];

    CLSUserInfo *copy = [orig copy];
    XCTAssertNoThrow([copy addExt:@"vB" key:@"kB"]);
    XCTAssertEqualObjects(copy.ext[@"kA"], @"vA");
    XCTAssertEqualObjects(copy.ext[@"kB"], @"vB");

    XCTAssertNil(orig.ext[@"kB"]);
    XCTAssertEqualObjects(orig.ext[@"kA"], @"vA");
    XCTAssertEqualObjects(copy.uid, @"u1");
    XCTAssertEqualObjects(copy.channel, @"c1");
}

- (void)testUserInfoCopy_IsIndependentFromOriginal {
    CLSUserInfo *orig = [CLSUserInfo userInfo];
    [orig addExt:@"v" key:@"shared"];

    CLSUserInfo *copy = [orig copy];
    [copy addExt:@"copy_only" key:@"onlyInCopy"];
    [orig addExt:@"orig_only" key:@"onlyInOrig"];

    XCTAssertNil(orig.ext[@"onlyInCopy"]);
    XCTAssertNil(copy.ext[@"onlyInOrig"]);
    XCTAssertEqualObjects(orig.ext[@"shared"], @"v");
    XCTAssertEqualObjects(copy.ext[@"shared"], @"v");
}

@end


