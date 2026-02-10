//
//  CLSAttribute.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import <Foundation/Foundation.h>
#import "CLSKeyValue.h"

NS_ASSUME_NONNULL_BEGIN

@interface CLSAttribute : NSObject
@property(nonatomic, strong) NSString* key;
@property(nonatomic, strong) id value;

+ (CLSAttribute*) of: (NSString *) key value: (NSString*)value;
+ (CLSAttribute*) of: (NSString *) key dictValue: (NSDictionary*)value;
+ (CLSAttribute*) of: (NSString *) key arrayValue: (NSArray*)value;

+ (NSArray<CLSAttribute*> *) of: (CLSKeyValue *) keyValue, ... NS_REQUIRES_NIL_TERMINATION;

+ (NSArray *) toArray: (NSArray<CLSAttribute *> *) attributes;

@end

NS_ASSUME_NONNULL_END
