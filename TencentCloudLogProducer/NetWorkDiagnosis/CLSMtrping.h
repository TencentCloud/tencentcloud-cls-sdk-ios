//
//  CLSMtrping.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/20.
//

#import <Foundation/Foundation.h>
#import "ClsProtocols.h"

NS_ASSUME_NONNULL_BEGIN

@interface CLSMtrResult : NSObject

@property (nonatomic, assign) BOOL success;
@property (nonatomic, assign) NSTimeInterval totalTime;

@property (nonatomic, strong) NSDictionary *netOrigin;
@property (nonatomic, strong) NSDictionary *netInfo;
@property (nonatomic, strong) NSArray *paths;
@property (nonatomic, strong, nullable) NSDictionary *detectEx;
@property (nonatomic, strong, nullable) NSDictionary *userEx;

@end


@interface CLSMultiInterfaceMtr : CLSBaseFields
@property (nonatomic, strong, readonly) CLSMtrRequest *request;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *pathsResults;
@property (nonatomic, strong) NSString *currentInterface;
@property (nonatomic, strong) NSDictionary *interfaceInfo;
@property (nonatomic, assign) BOOL isCompleted;
@property (nonatomic, assign) int sockfd;
@property (nonatomic, assign) int bindFailedCount;
@property (nonatomic, copy) void (^completionHandler)(CLSMtrResult *result, NSError *error);

- (instancetype)initWithRequest:(CLSMtrRequest *)request;
- (void)start:(CompleteCallback)complate;
@end

NS_ASSUME_NONNULL_END
