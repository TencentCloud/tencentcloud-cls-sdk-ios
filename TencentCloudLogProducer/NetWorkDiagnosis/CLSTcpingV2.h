//
//  CLSTcping.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/15.
//

#import <Foundation/Foundation.h>
#import "ClsProtocols.h"

// CLSMultiInterfaceTcpingResult.h
//基础信息
@interface CLSMultiInterfaceTcpingResult : NSObject
@property (nonatomic, copy) NSString *netType;
@property (nonatomic, copy) NSString *eventType;


//详细网络信息
@property (nonatomic, strong) NSDictionary *netOrigin;
@property (nonatomic, strong) NSDictionary *netInfo;
@property (nonatomic, strong) NSDictionary *detectEx;
@property (nonatomic, strong) NSDictionary *userEx;

//状态信息
@property (nonatomic, assign) BOOL success;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, assign) NSTimeInterval totalTime;
@end

@interface CLSMultiInterfaceTcping : CLSBaseFields
@property (nonatomic, strong) CLSTcpRequest *request;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *latencies;
@property (nonatomic, assign) NSUInteger successCount;
@property (nonatomic, assign) NSUInteger failureCount;
@property (nonatomic, assign) NSUInteger bindFailedCount;
@property (nonatomic, strong) NSDictionary *interface;
@property (nonatomic, copy) void (^completionHandler)(CLSMultiInterfaceTcpingResult *result, NSError *error);
@property (nonatomic, strong) dispatch_source_t timeoutTimer;
@property (nonatomic, assign) BOOL isCompleted;

- (instancetype)initWithRequest:(CLSTcpRequest *)request;
- (void)start:(CLSTcpRequest *) request complate:(CompleteCallback)complate;
@end



