//
//  CLSNetworkDiagnosisPlugin.m
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import "ClsNetworkDiagnosisPlugin.h"
#import "ClsNetWorkDataSender.h"

@implementation CLSNetworkDiagnosisPlugin
- (NSString *) name {
    return @"ClsNetworkDiagnosis";
}

- (BOOL) initWithCLSConfig: (ClsConfig *) config {
    _sender = [[CLSNetWorkDataSender alloc] init];
    [_sender initWithCLSConfig:config];
    _networkDiagnosis = [ClsNetworkDiagnosis sharedInstance];
    [_networkDiagnosis initWithConfig:config sender:_sender];
    return YES;
}
@end
