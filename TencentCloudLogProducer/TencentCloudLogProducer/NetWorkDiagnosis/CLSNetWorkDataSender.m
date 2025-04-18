//
//  CLSNetWorkDataSender.m
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import "CLSNetWorkDataSender.h"
#import "CLSNetWorkScheme.h"
#import "LogProducerClient.h"
#import "CLSUtils.h"
@implementation CLSNetWorkDataSender
- (void) initWithCLSConfig: (CLSConfig *)config{
    _networkconfig = config;
    _config = [[LogProducerConfig alloc] initWithCoreInfo:config.endpoint accessKeyID:config.accessKeyId accessKeySecret:config.accessKeySecret];
    [_config SetTopic:config.topicId];
    [_config SetPackageLogCount:1024];
    [_config SetPackageTimeout:3000];
    [_config SetMaxBufferLimit:64*1024*1024];
    [_config SetSendThreadCount:1];
    [_config SetConnectTimeoutSec:10];
    [_config SetSendTimeoutSec:10];
    [_config SetDestroyFlusherWaitSec:1];
    [_config SetDestroySenderWaitSec:1];
    [_config SetCompressType:1];
    [_config SetRetries:3];
    [_config SetMaxRetryBackoffMs:3000];
}

- (instancetype)sharedInstance:(LogProducerConfig *)logProducerConfig {
    static LogProducerClient * ins = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ins = [[LogProducerClient alloc] initWithClsLogProducer:logProducerConfig callback:nil];
    });
    return ins;
}

- (BOOL) sendDada: (Log *)log {
    if(nil == _config) {
        return NO;
    }
    
    if(nil == log) {
        return NO;
    }
    
    LogProducerClient *client = [self sharedInstance:_config];
    
    return LogProducerOK == [client PostLog:log];
}

- (BOOL) report: (NSString *) data method: (NSString *) method domain: (NSString *) domain customFiled: (NSMutableDictionary*) customFiled{
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
    
    __block Log *log = [[Log alloc] init];
    // not ignore global ext fields
    [[scheme toDictionaryWithIgnoreExt: NO] enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        [log PutContent:key value:obj];
    }];
    if (customFiled != nil && customFiled.count > 0){
        for (id key in customFiled) {
            [log PutContent:key value:customFiled[key]];
        }
    }
    return [self sendDada:log];
}
@end
