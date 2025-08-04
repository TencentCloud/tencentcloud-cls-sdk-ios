//
//  CLSNetWorkDataSender.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>
#import <TencentCloudLogProducer.h>
#import "ClsConfig.h"
#import "baseClsSender.h"
NS_ASSUME_NONNULL_BEGIN

@interface CLSNetWorkDataSender : baseClsSender
@property(nonatomic, strong) ClsLogProducerConfig *config;
@property(nonatomic, strong) ClsConfig *networkconfig;
- (BOOL) clsReport: (NSString *) data method: (NSString *) method domain: (NSString *) domain;
@end

NS_ASSUME_NONNULL_END
