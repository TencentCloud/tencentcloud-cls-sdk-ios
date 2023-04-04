//
//  CLSPing.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>
#import "CLSProtocols.h"
#import "baseSender.h"

NS_ASSUME_NONNULL_BEGIN
extern const int kCLSInvalidPingResponse;

@interface CLSPingResult : NSObject

@property (readonly) NSInteger code;
@property (readonly) NSString* err_msg;
@property (readonly) NSString* ip;
@property (readonly) NSString* domain;
@property (readonly) NSUInteger size;
@property (readonly) NSTimeInterval maxRtt;
@property (readonly) NSTimeInterval minRtt;
@property (readonly) NSTimeInterval avgRtt;
@property (readonly) NSInteger loss;
@property (readonly) NSInteger count;
@property (readonly) NSTimeInterval totalTime;
@property (readonly) NSTimeInterval stddev;

- (instancetype)init:(NSInteger)code
                err_msg:(NSString*)err_msg
                  ip:(NSString *)ip
              domain:(NSString *)domain
                size:(NSUInteger)size
                 max:(NSTimeInterval)maxRtt
                 min:(NSTimeInterval)minRtt
                 avg:(NSTimeInterval)avgRtt
                loss:(NSInteger)loss
               count:(NSInteger)count
           totalTime:(NSTimeInterval)totalTime
              stddev:(NSTimeInterval)stddev;
- (NSString*)description;
@end

typedef void (^CLSPingCompleteHandler)(CLSPingResult*);

@interface CLSPing : NSObject<CLSStopDelegate>

+ (instancetype)start:(NSString*)host
                 size:(NSUInteger)size
               output:(id<CLSOutputDelegate>)output
             complete:(CLSPingCompleteHandler)complete
               sender: (baseSender *)sender;

+ (instancetype)start:(NSString*)host
                 size:(NSUInteger)size
               output:(id<CLSOutputDelegate>)output
             complete:(CLSPingCompleteHandler)complete
               sender: (baseSender *)sender
                count:(NSInteger)count;

//@interface CLSPing ()
@property (readonly) NSString *host;
@property (nonatomic, assign) NSUInteger size;
@property (nonatomic, strong) id<CLSOutputDelegate> output;
@property (readonly) CLSPingCompleteHandler complete;
@property(nonatomic, strong) baseSender *sender;
@property (readonly) NSInteger count;
@property (atomic) BOOL stopped;

@end

NS_ASSUME_NONNULL_END
