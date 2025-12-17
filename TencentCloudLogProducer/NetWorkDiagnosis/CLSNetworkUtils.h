//
//  CLSNetworkUtils.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/13.
//

// CLSNetworkUtils.h
#import <Foundation/Foundation.h>
#import "ClsProtocols.h"

NS_ASSUME_NONNULL_BEGIN

@interface CLSNetworkUtils : NSObject

+ (NSDictionary *)parseNetToken:(NSString *)netToken;

// 获取网络环境信息
+ (NSDictionary *)getNetworkEnvironmentInfo:(NSString *)usedNet networkAppId:(NSString *)networkAppId appKey:(NSString *)appKey uin:(NSString *)uin endpoint:(NSString *)endpoint;

// 获取网卡绑定的ip
+ (NSString *)getIPAddressForInterface:(NSString *)interfaceName;

// 获取SDK构建信息
+ (NSString *)getSDKBuildTime;

+ (NSArray<NSDictionary *> *)getAllNetworkInterfacesDetail;

+ (NSArray<NSDictionary *> *)getAvailableInterfacesForType;

+ (NSInteger)ping:(struct sockaddr_in *)addr seq:(uint16_t)seq
       identifier:(uint16_t)identifier
             sock:(int)sock
              ttl:(int *)ttlOut
             size:(int *)size;

+ (BOOL)bindSocket:(int)socket toInterface:(NSString *)interfaceName;

+ (NSDictionary *)buildEnhancedNetworkInfoWithInterfaceType:(NSString *)interfaceType
                                             networkAppId:(NSString *)networkAppId
                                                    appKey:(NSString *)appKey
                                                      uin:(NSString *)uin
                                                  endpoint:(NSString *)endpoint
                                               interfaceDNS:(NSString *)interfaceDNS;

@end

NS_ASSUME_NONNULL_END
