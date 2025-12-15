//
//  CLSDeviceUtils.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CLSDeviceUtils : NSObject

+ (NSString *) getDeviceModelIdentifier;
+ (NSString *) getDeviceModel;
+ (NSString *) isJailBreak;
+ (NSString *) getResolution;
+ (NSString *) getCarrier;
+ (NSString *) getNetworkTypeName;
+ (NSString *) getNetworkSubTypeName;
+ (NSString *) getCPUArch;
+ (NSString *) getReachabilityStatus;

@end

NS_ASSUME_NONNULL_END
