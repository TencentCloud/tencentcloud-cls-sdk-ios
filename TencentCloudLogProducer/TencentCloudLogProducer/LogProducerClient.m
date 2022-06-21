

#import <Foundation/Foundation.h>
#import "LogProducerClient.h"
#import "LogProducerConfig.h"
#import "Log.h"
#import "TimeUtils.h"



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
        
    }

    return self;
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

