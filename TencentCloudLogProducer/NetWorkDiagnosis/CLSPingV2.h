//
//  CLSPingV2.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/16.
//

#import <Foundation/Foundation.h>
#import "ClsProtocols.h"

// CLSPingConfiguration.h
//@interface CLSPingConfiguration : NSObject
//
//@property (nonatomic, copy) NSString *host;
//@property (nonatomic, copy) NSString *traceId;
//@property (nonatomic, copy) NSString *appKey;
//@property (nonatomic, assign) NSUInteger count;
//@property (nonatomic, assign) NSUInteger packetSize;
//@property (nonatomic, assign) NSTimeInterval timeout;
//@property (nonatomic, copy) NSString *interfaceName;
//@property (nonatomic, copy, nullable) NSString *pageName;
//@property (nonatomic, strong) NSDictionary *userEx;
//@property (nonatomic, strong) NSDictionary *detectEx;
//
//+ (instancetype)configurationWithHost:(NSString *)host
//                              traceId:(NSString *)traceId
//                               appKey:(NSString *)appKey;
//
//@end

@interface CLSMultiInterfacePingResult : NSObject

@property (nonatomic, copy) NSString *netType;
@property (nonatomic, copy) NSString *eventType;
@property (nonatomic, assign) BOOL success;
@property (nonatomic, assign) NSTimeInterval totalTime;
@property (nonatomic, strong) NSError *error;

// 网络探测详情
@property (nonatomic, strong) NSDictionary *netOrigin;
@property (nonatomic, strong) NSDictionary *netInfo;
@property (nonatomic, strong) NSDictionary *headers;
@property (nonatomic, strong) NSDictionary *desc;
@property (nonatomic, strong) NSDictionary *detectEx;
@property (nonatomic, strong) NSDictionary *userEx;

@end

@interface CLSMultiInterfacePing : CLSBaseFields

@property (nonatomic, strong) CLSPingRequest *request;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *latencies;
@property (nonatomic, assign) NSUInteger successCount;
@property (nonatomic, assign) NSUInteger failureCount;
@property (nonatomic, assign) NSUInteger bindFailedCount;
@property (nonatomic, strong) NSDictionary *interfaceInfo;
@property (nonatomic, copy) void (^completionHandler)(CLSMultiInterfacePingResult *result, NSError *error);
@property (nonatomic, strong) dispatch_source_t timeoutTimer;
@property (nonatomic, assign) BOOL isCompleted;

- (instancetype)initWithRequest:(CLSPingRequest *)request;
- (void)start:(CLSPingRequest *) request complate:(CompleteCallback)complate;

@end
