//
//  ClsNetworkDiagnosis.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>
#import "ClsProtocols.h"
#import "CLSHttpingV2.h"
#import "CLSTcpingV2.h"
#import "CLSPingV2.h"
#import "CLSDnsping.h"
#import "CLSMtrping.h"
#import "TencentCloudLogProducer/ClsLogSender.h"

NS_ASSUME_NONNULL_BEGIN

@interface ClsNetworkDiagnosis : NSObject
+ (instancetype)sharedInstance;
- (void)setupLogSenderWithConfig:(ClsLogSenderConfig *)config
                         topicId:(NSString * _Nullable)topicId
                        netToken:(NSString * _Nullable)netToken;
/*****协议升级以下是v2接口****/
- (void) httpingv2:(CLSHttpRequest *) request complate:(CompleteCallback)complate;
- (void) tcpPingv2:(CLSTcpRequest *) request complate:(CompleteCallback)complate;
- (void) pingv2:(CLSPingRequest *) request complate:(CompleteCallback)complate;
- (void) dns:(CLSDnsRequest *) request complate:(CompleteCallback)complate;
- (void) mtr:(CLSMtrRequest *) request complate:(CompleteCallback)complate;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
