//
//  CLSAttribute.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import "CLSAttribute.h"

@implementation CLSAttribute
+ (CLSAttribute*) of: (NSString *) key value: (NSString*)value {
    CLSAttribute *attribute = [[CLSAttribute alloc] init];
    attribute.key = key;
    attribute.value = value;
    return  attribute;
}

+ (CLSAttribute*) of: (NSString *) key dictValue: (NSDictionary*)value {
    CLSAttribute *attribute = [[CLSAttribute alloc] init];
    attribute.key = key;
    attribute.value = [value copy];
    return  attribute;
}

+ (CLSAttribute*) of: (NSString *) key arrayValue: (NSArray*)value {
    CLSAttribute *attribute = [[CLSAttribute alloc] init];
    attribute.key = key;
    attribute.value = value;
    return  attribute;
}

+ (NSArray<CLSAttribute*> *) of: (CLSKeyValue *) keyValue, ... NS_REQUIRES_NIL_TERMINATION {
    NSMutableArray<CLSAttribute*> * array = [NSMutableArray<CLSAttribute*> array];
    [array addObject:[self of:keyValue.key value:keyValue.value]];
    va_list args;
    CLSKeyValue *arg;
    va_start(args, keyValue);
    while ((arg = va_arg(args, CLSKeyValue*))) {
        [array addObject:[self of:arg.key value:arg.value]];
    }
    va_end(args);
    return  array;
}

+ (NSArray *) toArray: (NSArray<CLSAttribute *> *) attributes {
    NSMutableArray *array = [NSMutableArray array];
    for (CLSAttribute *attribute in attributes) {
        [array addObject:@{
            @"key": attribute.key,
            @"value": @{
                @"stringValue": attribute.value
            }
        }];
    }
    return array;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    CLSAttribute *attr = [[CLSAttribute alloc] init];
    attr.key = [self.key copy];
    attr.value = [self.value copy];
    return attr;
}

- (id)mutableCopyWithZone:(nullable NSZone *)zone {
    CLSAttribute *attr = [[CLSAttribute alloc] init];
    attr.key = [self.key copy];
    attr.value = [self.value copy];
    return attr;
}
@end

