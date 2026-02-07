//
//  CLSCocoa.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import <Foundation/Foundation.h>
#import "CLSSpanProviderProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class CLSExtraProvider;

@interface CLSSpanProviderDelegate : NSObject<CLSSpanProviderProtocol>

// 使用 extraProvider 初始化（用于传递探测场景的接口名称等信息）
- (instancetype)initWithExtraProvider:(CLSExtraProvider *)extraProvider;

@end

@interface CLSExtraProvider : NSObject
- (void) setExtra: (NSString *)key value: (NSString *)value;
- (void) setExtra: (NSString *)key dictValue: (NSDictionary<NSString *, NSString *> *)value;
- (void) removeExtra: (NSString *)key;
- (void) clearExtras;
- (NSDictionary<NSString *, NSString *> *) getExtras;
@end
NS_ASSUME_NONNULL_END

