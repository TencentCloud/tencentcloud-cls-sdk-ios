//
//  CLSNetWorkDataSender.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>
#import <TencentCloudLogProducer.h>
#import "CLSConfig.h"
#import "baseSender.h"
NS_ASSUME_NONNULL_BEGIN

@interface CLSNetWorkDataSender : baseSender
@property(nonatomic, strong) LogProducerConfig *config;
@property(nonatomic, strong) CLSConfig *networkconfig;
- (BOOL) report: (NSString *) data method: (NSString *) method domain: (NSString *) domain;
@end

NS_ASSUME_NONNULL_END
