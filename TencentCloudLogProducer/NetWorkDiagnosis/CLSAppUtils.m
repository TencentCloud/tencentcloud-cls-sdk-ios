//
//  CLSAppUtils.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import "CLSAppUtils.h"

@implementation CLSAppUtils

+ (instancetype) sharedInstance {
    static CLSAppUtils *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CLSAppUtils alloc] init];
    });
    return instance;
}
@end
