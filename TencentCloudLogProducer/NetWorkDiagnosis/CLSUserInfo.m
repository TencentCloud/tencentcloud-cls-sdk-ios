//
//  CLSUserInfo.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import "CLSUserInfo.h"

@interface CLSUserInfo ()

@end

@implementation CLSUserInfo

+ (instancetype) userInfo {
    return [[CLSUserInfo alloc] init];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _ext = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void) addExt: (NSString *) value key: (NSString *) key {
    if (key && value) {
        [_ext setObject:value forKey:key];
    }
}

- (id)copyWithZone:(nullable NSZone *)zone {
    CLSUserInfo *info = [[CLSUserInfo alloc] init];
    info.uid = [self.uid copy];
    info.channel = [self.channel copy];
    info->_ext = [self.ext copy];
    return info;
}

@end
