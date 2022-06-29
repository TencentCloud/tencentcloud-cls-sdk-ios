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
#import "CLSProtocols.h"
#import "CLSTcpPing.h"
#import "CLSTraceRoute.h"

NS_ASSUME_NONNULL_BEGIN

@interface CLSNetworkDiagnosis : NSObject
+ (instancetype) sharedInstance;
- (void) initWithConfig: (CLSConfig *)config sender: (baseSender *)sender;

//ping
- (void)ping:(NSString*)host size:(NSUInteger)size output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete;
- (void)ping:(NSString*)host size:(NSUInteger)size output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete count:(NSInteger)count;

//tcpPing
- (void)tcpPing:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete;
- (void)tcpPing:(NSString*)host port:(NSUInteger)port count:(NSInteger)count output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete;
//
//traceroute
- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete;
- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete maxTtl:(NSInteger)maxTtl;
@end

NS_ASSUME_NONNULL_END
