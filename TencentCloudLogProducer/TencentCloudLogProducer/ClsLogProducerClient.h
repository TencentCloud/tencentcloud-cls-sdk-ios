

#ifndef CLS_LOG_PRODUCER_CLIENT_H
#define CLS_LOG_PRODUCER_CLIENT_H


#import "cls_log_producer_client.h"
#import "ClsLogProducerConfig.h"
#import "TencentCloudLogProducer/ClsLog.h"

typedef void (^AddClsLogInterceptor)(ClsLog *log);

@interface ClsLogProducerClient : NSObject
{
    @private clslogproducer* producer;
    @private clslogproducerclient* client;
    @private ClsLogProducerConfig* logConfig;
    @private BOOL enable;
}

typedef NS_ENUM(NSInteger, ClsLogProducerResult) {
    ClsLogProducerOK = 0,
    ClsLogProducerInvalid,
    ClsLogProducerWriteError,
    ClsLogProducerDropError,
    ClsLogProducerSendNetworkError,
    ClsLogProducerSendQuotaError,
    ClsLogProducerSendUnauthorized,
    ClsLogProducerSendServerError,
    ClsLogProducerSendDiscardError,
    ClsLogProducerSendTimeError,
    ClsLogProducerSendExitBufferdF,
    ClsLogProducerParametersInvalid,
    ClsLogProducerPERSISTENT_Error = 99
};

- (id) initWithClsLogProducer:(ClsLogProducerConfig *)logProducerConfig;

- (id) initWithClsLogProducer:(ClsLogProducerConfig *)logProducerConfig callback:(ClsSendCallBackFunc)callback;

- (void)DestroyClsLogProducer;

- (ClsLogProducerResult)PostClsLog:(ClsLog *) log;

- (void) UpdateSecurityToken:(NSString *)securityToken;

- (void) DiscardPersistentLog;

@end

struct SearchClsReult
{
    NSInteger statusCode;
    NSString* message;
    NSString* requestID;
};
typedef struct SearchClsReult SearchClsReult;
@interface ClsLogSearchClient : NSObject
{
}
-(SearchClsReult) SearchClsLog:(NSString*)region
                secretid:(NSString*) secretid
             secretkey:(NSString*) secretkey
              logsetid:(NSString*) logsetid
              topicids:(NSArray*) topicids
             starttime:(NSString*) starttime
               endtime:(NSString*) endtime
                 query:(NSString*) query
                 limit:(NSInteger)limit
               context:(NSString*)context
                    sort:(NSString*)sort;

-(id)init;
-(void) DestroyClsLogSearch;
@end

#endif /* LogProducerClient_h */
