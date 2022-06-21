

#ifndef LogProducerConfig_h
#define LogProducerConfig_h


#endif /* LogProducerConfig_h */

#import "log_producer_config.h"
#import "log_adaptor.h"


@interface LogProducerConfig : NSObject
{
    @package ProducerConfig* config;
    @private NSString *endpoint;
}

- (id) initWithCoreInfo:(NSString *) endpoint accessKeyID:(NSString *)accessKeyID accessKeySecret:(NSString *)accessKeySecret;

- (id) initWithCoreInfo:(NSString *) endpoint accessKeyID:(NSString *)accessKeyID accessKeySecret:(NSString *)accessKeySecret securityToken:(NSString *)securityToken;

- (void)SetTopic:(NSString *) topic;

- (void)SetPackageLogBytes:(int) num;

- (void)SetPackageLogCount:(int) num;

- (void)SetPackageTimeout:(int) num;

- (void)SetMaxBufferLimit:(int) num;

- (void)SetSendThreadCount:(int) num;

- (void)SetConnectTimeoutSec:(int) num;

- (void)SetSendTimeoutSec:(int) num;

- (void)SetRetries:(int) num;

- (void)SetBaseRetryBackoffMs:(int) num;

- (void)SetMaxRetryBackoffMs:(int) num;

- (void)SetDestroyFlusherWaitSec:(int) num;

- (void)SetDestroySenderWaitSec:(int) num;

- (void)SetCompressType:(int) num;

- (void) setEndpoint: (NSString *)endpoint;

- (NSString *)getEndpoint;

- (void) setAccessKeyId: (NSString *)accessKeyId;

- (void) setAccessKeySecret: (NSString *) accessKeySecret;

- (void) ResetSecurityToken:(NSString *)securityToken;

+ (void) Debug;

@end
