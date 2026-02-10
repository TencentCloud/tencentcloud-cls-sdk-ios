//
//  CLSEvent.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import <Foundation/Foundation.h>
#import "CLSAttribute.h"

NS_ASSUME_NONNULL_BEGIN

@interface CLSEvent : NSObject
@property(nonatomic, strong) NSString *name;
@property(atomic, assign) long epochNanos;
@property(atomic, assign) int totalAttributeCount;
@property(nonatomic, strong, readonly) NSArray<CLSAttribute *> *attributes;

+ (instancetype) eventWithName: (NSString *)name;

- (instancetype) addAttribute:(CLSAttribute *)attributes, ... NS_REQUIRES_NIL_TERMINATION NS_SWIFT_UNAVAILABLE("use addAttributes instead.");
- (instancetype) addAttributes:(NSArray<CLSAttribute *> *)attributes;

@end

NS_ASSUME_NONNULL_END
