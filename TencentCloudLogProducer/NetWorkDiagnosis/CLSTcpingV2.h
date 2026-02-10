//
//  CLSTcping.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/15.
//

#import <Foundation/Foundation.h>
#import "ClsProtocols.h"

@interface CLSMultiInterfaceTcping : CLSBaseFields
@property (nonatomic, strong) CLSTcpRequest *request;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *latencies;
@property (nonatomic, assign) NSUInteger successCount;
@property (nonatomic, assign) NSUInteger failureCount;
@property (nonatomic, assign) NSUInteger bindFailedCount;
@property (nonatomic, strong) NSDictionary *interface;
@property (nonatomic, copy) void (^completionHandler)(NSDictionary *reportData, NSError *error);
@property (nonatomic, strong) dispatch_source_t timeoutTimer;
@property (nonatomic, assign) BOOL isCompleted;

- (instancetype)initWithRequest:(CLSTcpRequest *)request;
- (void)start:(CompleteCallback)complate;
@end



