//
//  CLSNetworkDiagnosisPlugin.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>
#import <TencentCloudLogProducer.h>
#import "CLSNetWorkDataSender.h"
#import "CLSNetworkDiagnosis.h"
#import "baseSender.h"
NS_ASSUME_NONNULL_BEGIN

@interface CLSNetworkDiagnosisPlugin : baseSender
@property(nonatomic, strong) baseSender *sender;
@property(nonatomic, strong) CLSNetworkDiagnosis *networkDiagnosis;
@end

NS_ASSUME_NONNULL_END
