//
//  CLSPingV2.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/16.
//

#import <Foundation/Foundation.h>
#import "ClsProtocols.h"


@interface CLSMultiInterfacePing : CLSBaseFields
@property (nonatomic, strong) CLSPingRequest *request;
- (instancetype)initWithRequest:(CLSPingRequest *)request;
- (void)start:(CompleteCallback)complate;

@end
