//
//  CLS4Unity.m
//  TencentCloudLogProducer
//
//  Created by hanclli on 2025/10/24.
//  Updated for network detection API v2
//

#import <Foundation/Foundation.h>
#import "CLS4Unity.h"
#import "TencentCloudLogProducer/ClsNetworkDiagnosis.h"
#import "TencentCloudLogProducer/ClsLogSender.h"

// 初始化接口 - 使用 topicId
void cls_init(const char *endpoint, const char *accessKey, const char *accessSecret, const char *topicId)
{
    if (!endpoint || !accessKey || !accessSecret || !topicId) {
        return;
    }
    
    NSString *nsEndpoint = [NSString stringWithUTF8String:endpoint];
    NSString *nsAccessKey = [NSString stringWithUTF8String:accessKey];
    NSString *nsAccessSecret = [NSString stringWithUTF8String:accessSecret];
    NSString *nsTopicId = [NSString stringWithUTF8String:topicId];
    
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:nsEndpoint
                                                           accessKeyId:nsAccessKey
                                                             accessKey:nsAccessSecret];
    
    [[ClsNetworkDiagnosis sharedInstance] setupLogSenderWithConfig:config topicId:nsTopicId];
}

// 初始化接口 - 使用 netToken
void cls_init_with_net_token(const char *endpoint, const char *accessKey, const char *accessSecret, const char *netToken)
{
    if (!endpoint || !accessKey || !accessSecret || !netToken) {
        return;
    }
    
    NSString *nsEndpoint = [NSString stringWithUTF8String:endpoint];
    NSString *nsAccessKey = [NSString stringWithUTF8String:accessKey];
    NSString *nsAccessSecret = [NSString stringWithUTF8String:accessSecret];
    NSString *nsNetToken = [NSString stringWithUTF8String:netToken];
    
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:nsEndpoint
                                                           accessKeyId:nsAccessKey
                                                             accessKey:nsAccessSecret];
    
    [[ClsNetworkDiagnosis sharedInstance] setupLogSenderWithConfig:config netToken:nsNetToken];
}

// ICMP Ping 探测
void cls_ping(const char* host, unsigned int size, unsigned int maxTimes, unsigned int timeout, 
              int interval, int prefer, const char* appKey, const char* pageName,
              void(*callback)(const char*), NSDictionary* userEx, NSDictionary* detectEx)
{
    if (!host || !appKey) {
        return;
    }
    
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = [NSString stringWithUTF8String:host];
    request.appKey = [NSString stringWithUTF8String:appKey];
    request.size = size > 0 ? size : 64;
    request.maxTimes = maxTimes > 0 ? maxTimes : 10;
    request.timeout = timeout > 0 ? timeout : 15000;
    request.interval = interval > 0 ? interval : 200;
    request.prefer = prefer;
    
    if (pageName) {
        request.pageName = [NSString stringWithUTF8String:pageName];
    }
    
    // 直接设置自定义字段
    if (userEx) {
        request.userEx = userEx;
    }
    if (detectEx) {
        request.detectEx = detectEx;
    }
    
    [[ClsNetworkDiagnosis sharedInstance] pingv2:request complate:^(CLSResponse *response) {
        if (callback && response.content) {
            callback([response.content UTF8String]);
        }
    }];
}

// TCP 连接探测
void cls_tcp_ping(const char* host, unsigned int port, unsigned int maxTimes, unsigned int timeout,
                  const char* appKey, const char* pageName,
                  void(*callback)(const char*), NSDictionary* userEx, NSDictionary* detectEx)
{
    if (!host || !appKey) {
        return;
    }
    
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = [NSString stringWithUTF8String:host];
    request.appKey = [NSString stringWithUTF8String:appKey];
    request.port = port > 0 ? port : 80;
    request.maxTimes = maxTimes > 0 ? maxTimes : 10;
    request.timeout = timeout > 0 ? timeout : 15000;
    
    if (pageName) {
        request.pageName = [NSString stringWithUTF8String:pageName];
    }
    
    // 直接设置自定义字段
    if (userEx) {
        request.userEx = userEx;
    }
    if (detectEx) {
        request.detectEx = detectEx;
    }
    
    [[ClsNetworkDiagnosis sharedInstance] tcpPingv2:request complate:^(CLSResponse *response) {
        if (callback && response.content) {
            callback([response.content UTF8String]);
        }
    }];
}

// HTTP 探测
void cls_http_ping(const char* host, unsigned int maxTimes, unsigned int timeout, 
                   int enableSSLVerification, const char* appKey, const char* pageName,
                   void(*callback)(const char*), NSDictionary* userEx, NSDictionary* detectEx)
{
    if (!host || !appKey) {
        return;
    }
    
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = [NSString stringWithUTF8String:host];
    request.appKey = [NSString stringWithUTF8String:appKey];
    request.maxTimes = maxTimes > 0 ? maxTimes : 10;
    request.timeout = timeout > 0 ? timeout : 15000;
    request.enableSSLVerification = enableSSLVerification != 0;
    
    if (pageName) {
        request.pageName = [NSString stringWithUTF8String:pageName];
    }
    
    // 直接设置自定义字段
    if (userEx) {
        request.userEx = userEx;
    }
    if (detectEx) {
        request.detectEx = detectEx;
    }
    
    [[ClsNetworkDiagnosis sharedInstance] httpingv2:request complate:^(CLSResponse *response) {
        if (callback && response.content) {
            callback([response.content UTF8String]);
        }
    }];
}

// DNS 解析探测
void cls_dns_ping(const char* host, const char* nameServer, unsigned int timeout, 
                  int prefer, const char* appKey, const char* pageName,
                  void(*callback)(const char*), NSDictionary* userEx, NSDictionary* detectEx, const char* traceId)
{
    if (!host || !appKey) {
        return;
    }
    
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = [NSString stringWithUTF8String:host];
    request.appKey = [NSString stringWithUTF8String:appKey];
    request.timeout = timeout > 0 ? timeout : 15000;
    request.prefer = prefer;
    
    if (nameServer) {
        request.nameServer = [NSString stringWithUTF8String:nameServer];
    }
    
    if (pageName) {
        request.pageName = [NSString stringWithUTF8String:pageName];
    }
    
    if (traceId) {
        request.traceId = [NSString stringWithUTF8String:traceId];
    }
    
    // 直接设置自定义字段
    if (userEx) {
        request.userEx = userEx;
    }
    if (detectEx) {
        request.detectEx = detectEx;
    }
    
    [[ClsNetworkDiagnosis sharedInstance] dns:request complate:^(CLSResponse *response) {
        if (callback && response.content) {
            callback([response.content UTF8String]);
        }
    }];
}

// MTR 路径探测
void cls_mtr_ping(const char* host, unsigned int maxTTL, unsigned int maxTimes, unsigned int timeout,
                  const char* protocol, int prefer, const char* appKey, const char* pageName,
                  void(*callback)(const char*), NSDictionary* userEx, NSDictionary* detectEx)
{
    if (!host || !appKey) {
        return;
    }
    
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = [NSString stringWithUTF8String:host];
    request.appKey = [NSString stringWithUTF8String:appKey];
    request.maxTTL = maxTTL > 0 ? maxTTL : 64;
    request.maxTimes = maxTimes > 0 ? maxTimes : 3;
    request.timeout = timeout > 0 ? timeout : 30000;
    request.prefer = prefer;
    
    if (protocol) {
        request.protocol = [NSString stringWithUTF8String:protocol];
    } else {
        request.protocol = @"icmp";  // 默认使用 ICMP 协议
    }
    
    if (pageName) {
        request.pageName = [NSString stringWithUTF8String:pageName];
    }
    
    // 直接设置自定义字段
    if (userEx) {
        request.userEx = userEx;
    }
    if (detectEx) {
        request.detectEx = detectEx;
    }
    
    [[ClsNetworkDiagnosis sharedInstance] mtr:request complate:^(CLSResponse *response) {
        if (callback && response.content) {
            callback([response.content UTF8String]);
        }
    }];
}


