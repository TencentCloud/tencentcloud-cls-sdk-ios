//
//  CLSTraceRoute.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>
#import "ClsProtocols.h"
#import "baseClsSender.h"
NS_ASSUME_NONNULL_BEGIN

@interface CLSTraceRouteResult : NSObject

@property (readonly) NSInteger code;
@property (readonly) NSString* ip;
@property (readonly) NSString* content;

@end

typedef void (^CLSTraceRouteCompleteHandler)(CLSTraceRouteResult*);

@interface CLSTraceRoute : NSObject <CLSStopDelegate>
+ (instancetype)start:(NSString*)host
               output:(id<CLSOutputDelegate>)output
             complete:(CLSTraceRouteCompleteHandler)complete
               sender: (baseClsSender *)sender
        traceRouteExt: (NSMutableDictionary*) traceRouteExt;

+ (instancetype)start:(NSString*)host
               output:(id<CLSOutputDelegate>)output
             complete:(CLSTraceRouteCompleteHandler)complete
               sender: (baseClsSender *)sender
               maxTtl:(NSInteger)maxTtl
        traceRouteExt: (NSMutableDictionary*) traceRouteExt;

@end

NS_ASSUME_NONNULL_END
