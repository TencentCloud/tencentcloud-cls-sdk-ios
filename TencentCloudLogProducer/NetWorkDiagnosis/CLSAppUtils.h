//
//  CLSAppUtils.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CLSAppUtils : NSObject
@property(atomic, assign) long bootTime;
@property(atomic, assign) BOOL coldStart;

+ (instancetype) sharedInstance;


@end

NS_ASSUME_NONNULL_END

