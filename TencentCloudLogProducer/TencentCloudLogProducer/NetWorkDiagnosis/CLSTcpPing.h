//
//  CLSTcpPing.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>
#import "CLSProtocols.h"
#import "baseSender.h"
NS_ASSUME_NONNULL_BEGIN
@interface CLSTcpPingResult : NSObject

@property (readonly) NSInteger code;
@property (readonly) NSString* err_msg;
@property (readonly) NSString* ip;
@property (readonly) NSTimeInterval maxTime;
@property (readonly) NSTimeInterval minTime;
@property (readonly) NSTimeInterval avgTime;
@property (readonly) NSInteger loss;
@property (readonly) NSInteger count;
@property (readonly) NSTimeInterval totalTime;
@property (readonly) NSTimeInterval stddev;

- (NSString*)description;

@end

typedef void (^CLSTcpPingCompleteHandler)(CLSTcpPingResult*);

@interface CLSTcpPing : NSObject <CLSStopDelegate>

+ (instancetype)start:(NSString*)host
               output:(id<CLSOutputDelegate>)output
             complete:(CLSTcpPingCompleteHandler)complete
               sender: (baseSender *)sender;

+ (instancetype)start:(NSString*)host
                 port:(NSUInteger)port
                count:(NSInteger)count
               output:(id<CLSOutputDelegate>)output
             complete:(CLSTcpPingCompleteHandler)complete
               sender: (baseSender *)sender;

@end

NS_ASSUME_NONNULL_END
