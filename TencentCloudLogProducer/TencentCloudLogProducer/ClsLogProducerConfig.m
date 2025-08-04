

#ifdef DEBUG
#define CLSLog(...) NSLog(__VA_ARGS__)
#else
#define CLSLog(...)
#endif

#import <Foundation/Foundation.h>
#import "ClsLogProducerConfig.h"
#import "cls_log.h"
#import "ClsTimeUtils.h"


@interface ClsLogProducerConfig ()

@end

@implementation ClsLogProducerConfig

- (id) initClsWithCoreInfo:(NSString *) endpoint accessKeyID:(NSString *)accessKeyID accessKeySecret:(NSString *)accessKeySecret
{
    if (self = [super init])
    {
        self = [self initClsWithCoreInfo:endpoint accessKeyID:accessKeyID accessKeySecret:accessKeySecret securityToken:nil];
    }

    return self;
}

- (id) initClsWithCoreInfo:(NSString *) endpoint accessKeyID:(NSString *)accessKeyID accessKeySecret:(NSString *)accessKeySecret securityToken:(NSString *)securityToken{
    if (self = [super init])
    {
        self->config = ClsConstructLogConfig();
        setClsPackageTimeout(self->config, 3000);
        ClsSetLogCountLimit(self->config, 1024);
        SetClsPackageLogBytes(self->config, 1024*1024);
        cls_set_send_thread_count(self->config, 1);
        ClsSetTimeUnixFunc(time_func);
 
        [self SetClsEndpoint:endpoint];
        [self SetClsAccessKeyId:accessKeyID];
        [self SetClsAccessKeySecret:accessKeySecret];
        
        if([securityToken length] != 0){
            [self ResetClsSecurityToken:securityToken];
        }
    }

    return self;
}

unsigned int time_func() {
    NSInteger timeInMillis = [ClsTimeUtils getClsTimeInMilliis];
    return timeInMillis;
}

- (void)SetClsEndpoint:(NSString *)endpoint
{
    self->endpoint = endpoint;
    ClsSetEndpoint(self->config, [endpoint UTF8String]);
}

- (NSString *)GetClsEndpoint
{
    return self->endpoint;
}

- (void)SetClsTopic:(NSString *) topic
{
    const char *topicChar=[topic UTF8String];
    SetClsTopic(self->config, topicChar);
}

- (void)SetClsSource:(NSString *) source
{
    const char *sourceChar=[source UTF8String];
    SetClsSource(self->config, sourceChar);
}

- (void)SetClsPackageLogBytes:(int) num
{
    SetClsPackageLogBytes(self->config, num);
}

- (void)SetClsPackageLogCount:(int) num
{
    ClsSetLogCountLimit(self->config, num);
}

- (void)SetClsPackageTimeout:(int) num
{
    setClsPackageTimeout(self->config, num);
}

- (void)SetClsMaxBufferLimit:(int) num
{
    SetClsMaxBufferLimit(self->config, num);
}

- (void)SetClsSendThreadCount:(int) num
{
    cls_set_send_thread_count(self->config, num);
}

- (void)SetClsConnectTimeoutSec:(int) num;
{
    ClsSetConnectTtimeoutSec(self->config, num);
}

- (void)SetClsSendTimeoutSec:(int) num;
{
    SetClsSendTimeoutSec(self->config, num);
}

- (void)SetClsRetries:(int) num
{
    SetClsRetries(self->config, num);
}

- (void)SetClsBaseRetryBackoffMs:(int) num
{
    SetClsBaseRetryBackoffMs(self->config, num);
}

- (void)SetClsMaxRetryBackoffMs:(int) num{
    SetClsMaxRetryBackoffMs(self->config, num);
}

- (void)SetClsDestroyFlusherWaitSec:(int) num;
{
    SetClsDestroyFlusherWaitSec(self->config, num);
}

- (void)SetClsDestroySenderWaitSec:(int) num;
{
    SetClsDestroySenderWaitSec(self->config, num);
}

- (void)SetClsCompressType:(int) num;
{
    SetClsCompressType(self->config, num);
}

- (void)SetClsAccessKeyId:(NSString *)accessKeyId
{
    ClsSetAccessId(self->config, [accessKeyId UTF8String]);
}

- (void)SetClsAccessKeySecret:(NSString *)accessKeySecret
{
    ClsSetAccessKey(self->config, [accessKeySecret UTF8String]);
}


- (void) ResetClsSecurityToken:(NSString *)securityToken{
    if ([securityToken length] == 0) {
        return;
    }
    resetClsSecurityToken(self->config,[securityToken UTF8String]);
}


@end
