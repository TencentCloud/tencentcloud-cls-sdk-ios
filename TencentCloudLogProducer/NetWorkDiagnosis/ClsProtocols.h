//
//  CLSProtocols.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//


#import <Foundation/Foundation.h>
#import "CLSStringUtils.h"
#import "CLSResponse.h"

#pragma mark -- request
@interface CLSRequest : NSObject
@property(nonatomic, copy) NSString *domain;
@property(nonatomic, copy) NSString *appKey;
@property(atomic, assign) int size;
@property(atomic, assign) int maxTimes;
@property(atomic, assign) int timeout;
@property(nonatomic, assign) BOOL enableMultiplePortsDetect;
@property (nonatomic, copy, nullable) NSString *pageName;
@property(nonatomic, strong) NSDictionary<NSString*, NSString*> *userEx;
@property(nonatomic, strong) NSDictionary<NSString*, NSString*> *detectEx;
@end

@interface CLSHttpRequest : CLSRequest
@property (nonatomic, assign) BOOL enableSSLVerification;   // SSL验证
@end

@interface CLSTcpRequest : CLSRequest
@property(atomic, assign) NSInteger port;
@end

@interface CLSPingRequest : CLSRequest
@property(atomic, assign) int maxTTL;
@property(atomic, assign) int interval;
@end

@interface CLSDnsRequest : CLSRequest
@property(nonatomic, copy) NSString* nameServer;
@end

@interface CLSMtrRequest : CLSRequest
@property(atomic, assign) int maxHops;
@end

@protocol CLSStopDelegate <NSObject>

- (void)stop;

@end

@protocol CLSOutputDelegate <NSObject>

- (void)write:(NSString*)line;

@end

@interface CLSBaseFields : NSObject <NSURLSessionTaskDelegate>

/// 公共网络请求参数
@property (nonatomic, copy) NSString *networkAppId;
@property (nonatomic, copy) NSString *appKey;
@property (nonatomic, copy) NSString *uin;
@property (nonatomic, copy) NSString *topicId;
@property (nonatomic, copy) NSString *region;
@property (nonatomic, copy) NSString *endPoint;

@end

typedef void (^CompleteCallback)(CLSResponse *response);
