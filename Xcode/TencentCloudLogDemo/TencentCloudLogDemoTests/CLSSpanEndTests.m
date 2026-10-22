
#import <XCTest/XCTest.h>
#import <TencentCloudLogProducer/CLSSpan.h>
#import <TencentCloudLogProducer/CLSAttribute.h>

@interface CLSSpanEndTests : XCTestCase
@end

@implementation CLSSpanEndTests

- (CLSSpan *)makeSpan {
    CLSSpan *span = [[CLSSpan alloc] init];
    span.name = @"test";
    span.traceID = @"trace-1";
    span.start = (long)([[NSDate date] timeIntervalSince1970] * 1e9);
    return span;
}

#pragma mark - 场景 1：重复 end 不卡死后续方法

- (void)testEnd_FirstCallReturnsYES {
    CLSSpan *span = [self makeSpan];
    XCTAssertTrue([span end]);
}

- (void)testEnd_SecondCallReturnsNO {
    CLSSpan *span = [self makeSpan];
    [span end];
    XCTAssertFalse([span end], @"second end should return NO");
}

- (void)testEnd_SecondCall_DoesNotDeadlockToDict {
    CLSSpan *span = [self makeSpan];
    [span end];
    [span end];  // 制造锁泄漏（修复前）

    XCTestExpectation *done = [self expectationWithDescription:@"toDict returns"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *d = [span toDict];
        XCTAssertNotNil(d);
        [done fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:^(NSError *err) {
        if (err) XCTFail(@"toDict was blocked by leaked lock from double end()");
    }];
}

- (void)testEnd_SecondCall_DoesNotDeadlockAddAttribute {
    CLSSpan *span = [self makeSpan];
    [span end];
    [span end];

    XCTestExpectation *done = [self expectationWithDescription:@"addAttributes returns"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [span addAttributes:@[[CLSAttribute of:@"k" value:@"v"]]];
        [done fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:^(NSError *err) {
        if (err) XCTFail(@"addAttributes was blocked by leaked lock from double end()");
    }];
}

#pragma mark - 场景 2：scope 回调内嵌套访问同一 Span 不死锁

- (void)testEnd_ScopeCallback_CanAccessSpanWithoutDeadlock {
    CLSSpan *span = [self makeSpan];
    __block BOOL scopeInvoked = NO;
    __block NSDictionary *dictInScope = nil;
    [span setScope:^{
        scopeInvoked = YES;
        dictInScope = [span toDict];
    }];

    XCTestExpectation *done = [self expectationWithDescription:@"end returns"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [span end];
        [done fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:^(NSError *err) {
        if (err) XCTFail(@"end deadlocked when scope callback accessed the same span");
    }];
    XCTAssertTrue(scopeInvoked);
    XCTAssertNotNil(dictInScope);
}

- (void)testEnd_ScopeCallback_InvokedExactlyOnce_OnFirstEndOnly {
    CLSSpan *span = [self makeSpan];
    __block NSInteger invokeCount = 0;
    [span setScope:^{
        invokeCount++;
    }];
    XCTAssertTrue([span end]);
    XCTAssertFalse([span end]);  // 第二次 end 不应再触发 scope
    XCTAssertEqual(invokeCount, 1);
}

#pragma mark - 场景 3：toDict / addAttributes 在 end 之后仍可访问（不卡死）

- (void)testToDict_AfterEnd_StillWorks {
    CLSSpan *span = [self makeSpan];
    [span addAttributes:@[[CLSAttribute of:@"a" value:@"1"]]];
    [span end];
    NSDictionary *d = [span toDict];
    XCTAssertNotNil(d);
    XCTAssertEqualObjects(d[@"name"], @"test");
    XCTAssertEqualObjects(d[@"traceID"], @"trace-1");
}

@end
