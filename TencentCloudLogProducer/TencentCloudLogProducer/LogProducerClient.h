

#ifndef LogProducerClient_h
#define LogProducerClient_h


#endif /* LogProducerClient_h */

#import "log_producer_client.h"
#import "LogProducerConfig.h"
#import "Log.h"

typedef void (^AddLogInterceptor)(Log *log);

@interface LogProducerClient : NSObject
{
    @private clslogproducer* producer;
    @private clslogproducerclient* client;
    @private BOOL enable;
}

typedef NS_ENUM(NSInteger, LogProducerResult) {
    LogProducerOK = 0,
    LogProducerInvalid,
    LogProducerWriteError,
    LogProducerDropError,
    LogProducerSendNetworkError,
    LogProducerSendQuotaError,
    LogProducerSendUnauthorized,
    LogProducerSendServerError,
    LogProducerSendDiscardError,
    LogProducerSendTimeError,
    LogProducerSendExitBufferdF,
    LogProducerParametersInvalid,
    LogProducerPERSISTENT_Error = 99
};

- (id) initWithClsLogProducer:(LogProducerConfig *)logProducerConfig;

- (id) initWithClsLogProducer:(LogProducerConfig *)logProducerConfig callback:(SendCallBackFunc)callback;

- (void)DestroyLogProducer;

- (LogProducerResult)PostLog:(Log *) log;

- (LogProducerResult)PostLog:(Log *) log flush:(int) flush;

@end
