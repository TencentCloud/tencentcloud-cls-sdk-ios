//
//  CLSUtils.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CLSUtils : NSObject
+ (NSString *) getDeviceModelIdentifier;
+ (NSString *) getDeviceModel;
+ (NSString *) getResolution;
+ (NSString *) getCarrier;
+ (NSString *) getNetworkTypeName;
+ (NSString *) getNetworkSubTypeName;
+ (NSString *) getCPUArch;
@end

NS_ASSUME_NONNULL_END
