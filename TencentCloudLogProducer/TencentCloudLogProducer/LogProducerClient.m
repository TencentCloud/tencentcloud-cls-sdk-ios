

#import <Foundation/Foundation.h>
#import "LogProducerClient.h"
#import "LogProducerConfig.h"
#import "TencentCloudLogProducer/Log.h"
#import "TimeUtils.h"
#import "sds.h"



@interface LogProducerClient ()
@end

@implementation LogProducerClient

- (id) initWithClsLogProducer:(LogProducerConfig *)logProducerConfig
{
    return [self initWithClsLogProducer:logProducerConfig callback:nil];
}

- (id) initWithClsLogProducer:(LogProducerConfig *)logProducerConfig callback:(SendCallBackFunc)callback
{
    if (self = [super init])
    {
         ClsLogProducerInit(LOG_GLOBAL_ALL);
        self->producer = ConstructorClsLogProducer(logProducerConfig->config, *callback, nil);
        self->client = GetClsLogProducer(self->producer, nil);
        if(self->client == NULL){
            enable = false;
        }else{
            enable = YES;
        }
        self->logConfig = logProducerConfig;
        
    }
    return self;
}

- (void) UpdateSecurityToken:(NSString *)securityToken{
    if ([securityToken length] == 0) {
        return;
    }
    [logConfig ResetSecurityToken:securityToken];
}

- (void)DestroyLogProducer
{
    if (!enable) {
        return;
    }
    enable = NO;
    DestructorClsLogProducer(self->producer);
    ClsLogProducerDestroy();
}

- (LogProducerResult)PostLog:(Log *) log
{
    return [self PostLog:log flush:0];
}

- (LogProducerResult)PostLog:(Log *) log flush:(int) flush
{
    if (!enable || self->client == NULL || log == nil) {
        return LogProducerInvalid;
    }
    NSMutableDictionary *logContents = log->content;
    
    int pairCount = (int)[logContents count];
        
    char **keyArray = (char **)malloc(sizeof(char *)*(pairCount));
    char **valueArray = (char **)malloc(sizeof(char *)*(pairCount));
    
    int32_t *keyCountArray = (int32_t*)malloc(sizeof(int32_t)*(pairCount));
    int32_t *valueCountArray = (int32_t*)malloc(sizeof(int32_t)*(pairCount));
    
    
    int ids = 0;
    for (NSString *key in logContents) {
        NSString *value = logContents[key];

        char* keyChar=[self convertToChar:key];
        char* valueChar=[self convertToChar:value];

        keyArray[ids] = keyChar;  //记录contents 所有的key
        valueArray[ids] = valueChar; ////记录contents 所有的value
        keyCountArray[ids] = (int32_t)strlen(keyChar); //记录contents 所有的key的大小
        valueCountArray[ids] = (int32_t)strlen(valueChar); //记录contents 所有的value的大小
        
        ids = ids + 1;
    }
    
    
    int res = PostClsLog(self->client, log->logTime, pairCount, keyArray, keyCountArray, valueArray, valueCountArray, flush);
    
    for(int i=0;i<pairCount;i++) {
        free(keyArray[i]);
        free(valueArray[i]);
    }
    free(keyArray);
    free(valueArray);
    free(keyCountArray);
    free(valueCountArray);
    return res;
}

-(char*)convertToChar:(NSString*)strtemp
{
    NSUInteger len = [strtemp lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1;
    if (len > 1000000) return strdup([strtemp UTF8String]);
    char cStr [len];
    [strtemp getCString:cStr maxLength:len encoding:NSUTF8StringEncoding];
    return strdup(cStr);
}

@end



@implementation LogSearchClient
-(SearchReult) SearchLog:(NSString*)region secretid:(NSString*) secretid
             secretkey:(NSString*) secretkey
              logsetid:(NSString*) logsetid
              topicids:(NSArray*) topicids
             starttime:(NSString*) starttime
               endtime:(NSString*) endtime
                 query:(NSString*) query
                 limit:(NSInteger)limit
               context:(NSString*)context
                  sort:(NSString*)sort
{
    SearchReult result;
    char **topics = (char**)malloc(sizeof(char*)*128);
    for(int i = 0; i < topicids.count; i++){
        topics[i] = [topicids[i] UTF8String];
    }
    get_result r;
    memset(r.requestID, 0, 128);
    ClsSearchLog([region UTF8String],[secretid UTF8String] ,[secretkey UTF8String],[logsetid UTF8String],topics,topicids.count,[starttime UTF8String],[endtime UTF8String],[query UTF8String],limit,[context UTF8String],[sort UTF8String],&r);
    
    free(topics);
    result.statusCode = r.statusCode;
    result.message = r.message ? [NSString stringWithUTF8String:r.message] : nil;
    result.requestID = r.requestID ? [NSString stringWithUTF8String:r.requestID] : nil;
    free(r.message);
    return result;
}

-(id)init{
    self = [super init];
    ClsLogSearchLogInit();
    return self;
}
-(void) DestroyLogSearch{
    ClsLogSearchLogDestroy();
}
@end
