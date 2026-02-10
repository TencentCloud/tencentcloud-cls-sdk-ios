//
//  CLSKeyValue.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import "CLSKeyValue.h"

@implementation CLSKeyValue

+ (CLSKeyValue *) create: (NSString*) key value: (NSString*) value {
    CLSKeyValue *kv = [[CLSKeyValue alloc] init];
    kv.key = key;
    kv.value = value;
    return kv;
}

+ (CLSKeyValue *) key: (NSString *) key value: (NSString *) value {
    return [self create:key value:value];
}
@end
