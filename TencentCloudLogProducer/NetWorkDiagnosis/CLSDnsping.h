//
//  CLSDnsping.h
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/20.
//

#import <Foundation/Foundation.h>
#import "ClsProtocols.h"

NS_ASSUME_NONNULL_BEGIN

@class CLSDnsResult;
@class baseClsSender;
@class CLSSpanBuilder;

#pragma mark - DNS结果类

@interface CLSDnsResult : NSObject

@property (nonatomic, copy) NSString *netType;
@property (nonatomic, copy) NSString *eventType;
@property (nonatomic, assign) BOOL success;
@property (nonatomic, assign) NSTimeInterval totalTime;
@property (nonatomic, copy) NSDictionary *netOrigin;
@property (nonatomic, copy) NSDictionary *netInfo;
@property (nonatomic, copy, nullable) NSDictionary *detectEx;
@property (nonatomic, copy, nullable) NSDictionary *userEx;

// DNS报文解析相关字段
@property (nonatomic, copy) NSString *flags;
@property (nonatomic, copy) NSArray *querySection;
@property (nonatomic, copy) NSArray *answerSection;
@property (nonatomic, copy) NSArray *authoritySection;
@property (nonatomic, copy) NSArray *additionalSection;
@property (nonatomic, assign) int questionCount;
@property (nonatomic, assign) int answerCount;
@property (nonatomic, assign) int authorityCount;
@property (nonatomic, assign) int additionalCount;

- (instancetype)init;

@end

#pragma mark - 多接口DNS测试类

@interface CLSMultiInterfaceDns : CLSBaseFields

@property (nonatomic, strong, readonly) CLSDnsRequest *request;
@property (nonatomic, copy, nullable) void (^completionHandler)(CLSDnsResult *result, NSError *error);
- (instancetype)initWithRequest:(CLSDnsRequest *)request;
- (void)start:(CLSDnsRequest *) request complate:(CompleteCallback)complate;
- (void)performDnsResolution;
- (CLSDnsResult *)buildDnsResult;
- (NSDictionary *)buildNetOriginWithResult:(CLSDnsResult *)result;
- (NSDictionary *)buildEnhancedNetworkInfo;
- (NSNumber *)calculateStdDev;
+ (NSDictionary *)buildReportDataFromDnsResult:(CLSDnsResult *)result;

@end

#pragma mark - DNS解析工具类

@interface CLSDnsParser : NSObject
- (void)parseDnsResponse:(unsigned char *)response
                 length:(int)length
                  flags:(NSString * __autoreleasing *)flags
        questionSection:(NSMutableArray<NSDictionary *> * __autoreleasing *)questionSection
         answerSection:(NSMutableArray<NSDictionary *> * __autoreleasing *)answerSection
      authoritySection:(NSMutableArray<NSDictionary *> * __autoreleasing *)authoritySection
     additionalSection:(NSMutableArray<NSDictionary *> * __autoreleasing *)additionalSection
         questionCount:(int *)questionCount
          answerCount:(int *)answerCount
      authorityCount:(int *)authorityCount
     additionalCount:(int *)additionalCount;

@end

NS_ASSUME_NONNULL_END
