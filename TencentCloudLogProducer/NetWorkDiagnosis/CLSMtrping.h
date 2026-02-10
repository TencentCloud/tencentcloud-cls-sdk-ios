//
//  CLSMtrping.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/20.
//

#import <Foundation/Foundation.h>
#import "ClsProtocols.h"

NS_ASSUME_NONNULL_BEGIN


@interface CLSMultiInterfaceMtr : CLSBaseFields
@property (nonatomic, strong) CLSMtrRequest *request;
- (instancetype)initWithRequest:(CLSMtrRequest *)request;
- (void)start:(CompleteCallback)complate;
@end

NS_ASSUME_NONNULL_END
