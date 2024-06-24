//
//  CLSNetworkDiagnosis.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>
#import "CLSConfig.h"
#import "baseSender.h"
#import "CLSPing.h"
#import "CLSHttping.h"
#import "CLSProtocols.h"
#import "CLSTcpPing.h"
#import "CLSTraceRoute.h"

NS_ASSUME_NONNULL_BEGIN

@interface CLSNetworkDiagnosis : NSObject
+ (instancetype) sharedInstance;
- (void) initWithConfig: (CLSConfig *)config sender: (baseSender *)sender;

//ping
- (void)ping:(NSString*)host size:(NSUInteger)size output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete;
- (void)ping:(NSString*)host size:(NSUInteger)size task_timeout:(NSUInteger)task_timeout output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete count:(NSInteger)count;
- (void)ping:(NSString*)host size:(NSUInteger)size output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete customFiled:(NSMutableDictionary*) customFiled;
- (void)ping:(NSString*)host size:(NSUInteger)size task_timeout:(NSUInteger)task_timeout output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete count:(NSInteger)count customFiled:(NSMutableDictionary*) customFiled;

//tcpPing
- (void)tcpPing:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete;
- (void)tcpPing:(NSString*)host port:(NSUInteger)port task_timeout:(NSUInteger)task_timeout count:(NSInteger)count output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete;
- (void)tcpPing:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete customFiled:(NSMutableDictionary*) customFiled;
- (void)tcpPing:(NSString*)host port:(NSUInteger)port task_timeout:(NSUInteger)task_timeout count:(NSInteger)count output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete customFiled:(NSMutableDictionary*) customFiled;
//
//traceroute
- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete;
- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete maxTtl:(NSInteger)maxTtl;
- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete customFiled:(NSMutableDictionary*) customFiled;
- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete maxTtl:(NSInteger)maxTtl customFiled:(NSMutableDictionary*) customFiled;

//httping
- (void) httping:(NSString*)url output:(id<CLSOutputDelegate>)output complate:(CLSHttpCompleteHandler)complate;
- (void) httping:(NSString*)url output:(id<CLSOutputDelegate>)output complate:(CLSHttpCompleteHandler)complate customFiled:(NSMutableDictionary*) customFiled;

@end

NS_ASSUME_NONNULL_END
