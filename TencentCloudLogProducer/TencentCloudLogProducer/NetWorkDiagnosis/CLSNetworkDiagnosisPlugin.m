//
//  CLSNetworkDiagnosisPlugin.m
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import "CLSNetworkDiagnosisPlugin.h"
#import "CLSNetWorkDataSender.h"

@implementation CLSNetworkDiagnosisPlugin
- (NSString *) name {
    return @"CLSNetworkDiagnosis";
}

- (BOOL) initWithCLSConfig: (CLSConfig *) config {
    _sender = [[CLSNetWorkDataSender alloc] init];
    [_sender initWithCLSConfig:config];
    _networkDiagnosis = [CLSNetworkDiagnosis sharedInstance];
    [_networkDiagnosis initWithConfig:config sender:_sender];
    return YES;
}
@end
