//
//  CLSResource.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import <Foundation/Foundation.h>
#import "CLSAttribute.h"
#import "CLSKeyValue.h"

NS_ASSUME_NONNULL_BEGIN

@interface CLSResource : NSObject

@property(nonatomic, strong) NSArray<CLSAttribute*> *attributes;

#pragma mark - instance
+ (instancetype) resource;
+ (CLSResource *) of: (NSString *) key value: (NSString *) value;
+ (CLSResource *) of: (CLSKeyValue*) keyValue, ...NS_REQUIRES_NIL_TERMINATION NS_SWIFT_UNAVAILABLE("use of:value: instead.");
+ (CLSResource *) ofAttributes: (NSArray<CLSAttribute *> *) attributes;

#pragma mark - operation
- (void) add: (NSString *) key value: (NSString *) value;
- (void) add: (NSArray<CLSAttribute *> *) attributes;
- (void) merge: (CLSResource *) resource;

#pragma mark - serialization
- (NSDictionary *) toDictionary;
@end

NS_ASSUME_NONNULL_END
