//
//  CLSLink.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import <Foundation/Foundation.h>
#import "CLSAttribute.h"

NS_ASSUME_NONNULL_BEGIN

@interface CLSLink : NSObject
@property(nonatomic, strong) NSString *traceId;
@property(nonatomic, strong) NSString *spanId;
@property(nonatomic, strong, readonly) NSArray<CLSAttribute *> *attributes;

+ (instancetype) linkWithTraceId: (NSString *)traceId spanId:(NSString *)spanId;
- (instancetype) addAttribute:(CLSAttribute *)attributes, ... NS_REQUIRES_NIL_TERMINATION NS_SWIFT_UNAVAILABLE("use addAttributes instead.");
- (instancetype) addAttributes:(NSArray<CLSAttribute *> *)attributes;

@end

NS_ASSUME_NONNULL_END
