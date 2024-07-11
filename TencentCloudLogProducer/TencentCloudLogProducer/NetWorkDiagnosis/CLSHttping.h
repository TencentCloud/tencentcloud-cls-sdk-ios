#import "CLSProtocols.h"
#import "baseSender.h"
#import <Foundation/Foundation.h>

@interface CLSHttpResult : NSObject

@property (readonly) NSString* url;
@property (readonly) NSString* errMessage;
@property (readonly) NSTimeInterval requestTime;
@property (readonly) NSHTTPURLResponse * response;



- (NSString *)description;

- (instancetype)init:method:(NSString *)method
                 url:(NSString *)url
         requestTime:(NSTimeInterval)requestTime
            response:(NSHTTPURLResponse *)response
                 httpErr:(NSError*)err;

- (CLSHttpResult *)buildResult:(NSInteger)code
                            ip:(NSString *)ip
                            domain:(NSString *)domain
                     durations:(NSTimeInterval *)durations
                         count:(NSInteger)count
                          loss:(NSInteger)loss
                     totalTime:(NSTimeInterval)time ;

@end

typedef void (^CLSHttpCompleteHandler)(CLSHttpResult*);

@interface CLSHttp : NSObject <CLSStopDelegate>

/**
 *    default port is 80
 *
 *    @param host     domain or ip
 *    @param output   output logger
 *    @param complete complete callback, maybe null
 *
 *    @return QNNTcpping instance, could be stop
 */
+ (instancetype)start:(NSString*)url
               output:(id<CLSOutputDelegate>)output
             complete:(CLSHttpCompleteHandler)complete
               sender: (baseSender *)sender
           httpingExt: (NSMutableDictionary*) httpingExt;

@property(nonatomic, strong) baseSender *sender;
@property(nonatomic, strong) NSMutableDictionary *httpingExt;

@end
