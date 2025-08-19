//
//  CLSNetWorkDataSender.m
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import "ClsNetWorkDataSender.h"
#import "ClsNetWorkScheme.h"
#import "ClsLogProducerClient.h"
#import "ClsUtils.h"
@implementation CLSNetWorkDataSender
- (void) initWithCLSConfig: (ClsConfig *)config{
    _networkconfig = config;
    _config = [[ClsLogProducerConfig alloc] initClsWithCoreInfo:config.endpoint accessKeyID:config.accessKeyId accessKeySecret:config.accessKeySecret];
    [_config SetClsTopic:config.topicId];
    [_config SetClsPackageLogCount:1024];
    [_config SetClsPackageTimeout:3000];
    [_config SetClsMaxBufferLimit:64*1024*1024];
    [_config SetClsSendThreadCount:1];
    [_config SetClsConnectTimeoutSec:10];
    [_config SetClsSendTimeoutSec:10];
    [_config SetClsDestroyFlusherWaitSec:1];
    [_config SetClsDestroySenderWaitSec:1];
    [_config SetClsCompressType:1];
    [_config SetClsRetries:3];
    [_config SetClsMaxRetryBackoffMs:3000];
}

- (instancetype)sharedInstance:(ClsLogProducerConfig *)logProducerConfig {
    static ClsLogProducerConfig * ins = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ins = [[ClsLogProducerClient alloc] initWithClsLogProducer:logProducerConfig callback:nil];
    });
    return ins;
}

- (BOOL) sendDada: (ClsLog *)log {
    if(nil == _config) {
        return NO;
    }
    
    if(nil == log) {
        return NO;
    }
    
    ClsLogProducerClient *client = [self sharedInstance:_config];
    
    return ClsLogProducerOK == [client PostClsLog:log];
}

- (BOOL) clsReport: (NSString *) data method: (NSString *) method domain: (NSString *) domain customFiled: (NSMutableDictionary*) customFiled{
    CLSNetWorkScheme *scheme = [CLSNetWorkScheme createDefaultWithCLSConfig:_networkconfig];
    if (scheme.app_id && [scheme.app_id containsString:@"@"]) {
        NSRange atRange = [scheme.app_id rangeOfString:@"@"];
        [scheme setApp_id:[scheme.app_id substringWithRange:NSMakeRange(0, atRange.location)]];
    }
    
//    [scheme setDomain: domain];
    [scheme setResult: data];
    [scheme setMethod: method];
    [scheme setDns:[CLSUtils GetDNSServers]];

//    NSMutableDictionary *reserves = [NSMutableDictionary dictionary];
//    [reserves setObject:[method uppercaseString] forKey:@"method"];

    // put ext fields to reserves
//    if (_networkconfig.ext) {
//        for (NSString *key in _networkconfig.ext) {
//            [reserves setObject:_networkconfig.ext[key] forKey:key];
//        }
//    }
    
//    NSData *json = [NSJSONSerialization dataWithJSONObject:reserves options:0 error:nil];
//    scheme.reserves = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    
    __block ClsLog *log = [[ClsLog alloc] init];
    // not ignore global ext fields
    [[scheme toDictionaryWithIgnoreExt: NO] enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        [log PutClsContent:key value:obj];
    }];
    if (customFiled != nil && customFiled.count > 0){
        for (id key in customFiled) {
            [log PutClsContent:key value:customFiled[key]];
        }
    }
    return [self sendDada:log];
}
@end
