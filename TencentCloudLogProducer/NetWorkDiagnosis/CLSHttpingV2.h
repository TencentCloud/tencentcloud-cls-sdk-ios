//
//  CLSHttpingV2.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/13.
//

#import <Foundation/Foundation.h>
#import "ClsProtocols.h"

NS_ASSUME_NONNULL_BEGIN

@interface CLSHttpingResult : NSObject

// 基础信息
@property (nonatomic, copy, nullable) NSString *pageName;

// 详细网络信息
@property (nonatomic, strong) NSDictionary *netOrigin;
@property (nonatomic, strong) NSDictionary *headers;
@property (nonatomic, strong) NSDictionary *desc;
@property (nonatomic, strong) NSDictionary *netInfo;
@property (nonatomic, strong, nullable) NSDictionary *detectEx;
@property (nonatomic, strong, nullable) NSDictionary *userEx;

// 状态信息
@property (nonatomic, assign) BOOL success;
@property (nonatomic, strong, nullable) NSError *error;
@property (nonatomic, assign) NSTimeInterval totalTime;

@end

@interface CLSMultiInterfaceHttping : CLSBaseFields
@property (nonatomic, strong) NSURLSession *urlSession;
@property (nonatomic, strong) NSMutableDictionary *timingMetrics;
@property (nonatomic, assign) CFAbsoluteTime taskStartTime;
@property (nonatomic, assign) CFAbsoluteTime processStartTime;
@property (nonatomic, assign) NSUInteger receivedBytes;
@property (nonatomic, strong) NSMutableData *responseData;
@property (nonatomic, copy) void (^completionHandler)(NSDictionary *resultDict, NSError *error);
@property (nonatomic, strong) NSDictionary *interfaceInfo;
@property (nonatomic, strong) dispatch_source_t timeoutTimer;
@property (nonatomic, strong, readonly) CLSHttpRequest *request;

- (instancetype)initWithRequest:(CLSHttpRequest *)request;
- (void)start:(CompleteCallback)complate;
@end

NS_ASSUME_NONNULL_END
