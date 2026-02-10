//
//  CLSSPanBuilder.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import <Foundation/Foundation.h>
#import "CLSSpan.h"
#import "CLSAttribute.h"
#import "CLSResource.h"
#import "CLSSpanProviderProtocol.h"

NS_ASSUME_NONNULL_BEGIN
@class CLSSpanBuilder;

@interface CLSSpanBuilder : NSObject
#pragma mark - instance
+ (CLSSpanBuilder *) builder;
- (CLSSpanBuilder *) initWithName: (NSString *)name provider: (id<CLSSpanProviderProtocol>) provider;

#pragma mark - setter
- (CLSSpanBuilder *) setActive: (BOOL) active;
- (CLSSpanBuilder *) addAttribute: (CLSAttribute *) attribute, ... NS_REQUIRES_NIL_TERMINATION NS_SWIFT_UNAVAILABLE("use addAttributes instead.");
- (CLSSpanBuilder *) addAttributes: (NSArray<CLSAttribute *> *) attributes NS_SWIFT_NAME(addAttributes(_:));
- (CLSSpanBuilder *) setStart: (long) start;
- (CLSSpanBuilder *) addResource: (CLSResource *) resource NS_SWIFT_NAME(addResource(_:));
- (CLSSpanBuilder *) setService: (NSString *)service;
- (CLSSpanBuilder *) setGlobal: (BOOL) global;
- (CLSSpanBuilder *) setURL: (NSString *)url;
- (CLSSpanBuilder *) setpageName: (NSString *)pageName;
- (CLSSpanBuilder *) setTraceId: (NSString *)traceId;
#pragma mark - build
- (CLSSpan *) build;
- (NSDictionary *)report:(NSString*)topicId reportData:(NSDictionary *)reportData;
@end

NS_ASSUME_NONNULL_END
