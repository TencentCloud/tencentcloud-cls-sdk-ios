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

/// 初始化方法（二选一）
- (void)setupLogSenderWithConfig:(ClsLogSenderConfig *)config
                        netToken:(NSString * _Nullable)netToken;
- (void)setupLogSenderWithConfig:(ClsLogSenderConfig *)config
                         topicId:(NSString * _Nullable)topicId;

/// 设置全局 userEx（后续所有探测上报时会携带此字段）
/// @param userEx 用户自定义扩展字段（key-value 字典）
- (void)setUserEx:(NSDictionary<NSString*, NSString*> * _Nullable)userEx;

/// 获取当前设置的全局 userEx
- (NSDictionary<NSString*, NSString*> * _Nullable)getUserEx;
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
