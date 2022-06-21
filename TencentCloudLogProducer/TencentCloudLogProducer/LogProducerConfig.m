

#ifdef DEBUG
#define CLSLog(...) NSLog(__VA_ARGS__)
#else
#define CLSLog(...)
#endif

#import <Foundation/Foundation.h>
#import "LogProducerConfig.h"
#import "cls_log.h"
#import "TimeUtils.h"


@interface LogProducerConfig ()

@end

@implementation LogProducerConfig

- (id) initWithCoreInfo:(NSString *) endpoint accessKeyID:(NSString *)accessKeyID accessKeySecret:(NSString *)accessKeySecret
{
    if (self = [super init])
    {
        self = [self initWithCoreInfo:endpoint accessKeyID:accessKeyID accessKeySecret:accessKeySecret securityToken:nil];
    }

    return self;
}

- (id) initWithCoreInfo:(NSString *) endpoint accessKeyID:(NSString *)accessKeyID accessKeySecret:(NSString *)accessKeySecret securityToken:(NSString *)securityToken{
    if (self = [super init])
    {
        self->config = ConstructLogConfig();
        setPackageTimeout(self->config, 3000);
        SetLogCountLimit(self->config, 1024);
        SetPackageLogBytes(self->config, 1024*1024);
        set_send_thread_count(self->config, 1);
        SetTimeUnixFunc(time_func);
 
        [self setEndpoint:endpoint];
        [self setAccessKeyId:accessKeyID];
        [self setAccessKeySecret:accessKeySecret];
        
        if([securityToken length] != 0){
            [self ResetSecurityToken:securityToken];
        }
    }

    return self;
}

unsigned int time_func() {
    NSInteger timeInMillis = [TimeUtils getTimeInMilliis];
    return timeInMillis;
}

- (void)setEndpoint:(NSString *)endpoint
{
    self->endpoint = endpoint;
    SetEndpoint(self->config, [endpoint UTF8String]);
}

- (NSString *)getEndpoint
{
    return self->endpoint;
}

- (void)SetTopic:(NSString *) topic
{
    const char *topicChar=[topic UTF8String];
    SetTopic(self->config, topicChar);
}

- (void)SetPackageLogBytes:(int) num
{
    SetPackageLogBytes(self->config, num);
}

- (void)SetPackageLogCount:(int) num
{
    SetLogCountLimit(self->config, num);
}

- (void)SetPackageTimeout:(int) num
{
    setPackageTimeout(self->config, num);
}

- (void)SetMaxBufferLimit:(int) num
{
    SetMaxBufferLimit(self->config, num);
}

- (void)SetSendThreadCount:(int) num
{
    set_send_thread_count(self->config, num);
}

- (void)SetConnectTimeoutSec:(int) num;
{
    SetConnectTtimeoutSec(self->config, num);
}

- (void)SetSendTimeoutSec:(int) num;
{
    SetSendTimeoutSec(self->config, num);
}

- (void)SetRetries:(int) num
{
    SetRetries(self->config, num);
}

- (void)SetBaseRetryBackoffMs:(int) num
{
    SetBaseRetryBackoffMs(self->config, num);
}

- (void)SetMaxRetryBackoffMs:(int) num{
    SetMaxRetryBackoffMs(self->config, num);
}

- (void)SetDestroyFlusherWaitSec:(int) num;
{
    SetDestroyFlusherWaitSec(self->config, num);
}

- (void)SetDestroySenderWaitSec:(int) num;
{
    SetDestroySenderWaitSec(self->config, num);
}

- (void)SetCompressType:(int) num;
{
    SetCompressType(self->config, num);
}

- (void)setAccessKeyId:(NSString *)accessKeyId
{
    SetAccessId(self->config, [accessKeyId UTF8String]);
}

- (void)setAccessKeySecret:(NSString *)accessKeySecret
{
    SetAccessKey(self->config, [accessKeySecret UTF8String]);
}


- (void) ResetSecurityToken:(NSString *)securityToken{
    if ([securityToken length] == 0) {
        return;
    }
    resetSecurityToken(self->config,[securityToken UTF8String]);
}

+ (void)Debug
{
    cls_log_set_level(CLS_LOG_DEBUG);
}


@end
