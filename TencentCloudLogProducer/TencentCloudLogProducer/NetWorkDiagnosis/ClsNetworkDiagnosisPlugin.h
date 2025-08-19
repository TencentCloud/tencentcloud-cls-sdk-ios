//
//  CLSNetworkDiagnosisPlugin.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>
#import <TencentCloudLogProducer.h>
#import "ClsNetWorkDataSender.h"
#import "ClsNetworkDiagnosis.h"
#import "baseClsSender.h"
NS_ASSUME_NONNULL_BEGIN

@interface CLSNetworkDiagnosisPlugin : baseClsSender
@property(nonatomic, strong) baseClsSender *sender;
@property(nonatomic, strong) ClsNetworkDiagnosis *networkDiagnosis;
@end

NS_ASSUME_NONNULL_END
