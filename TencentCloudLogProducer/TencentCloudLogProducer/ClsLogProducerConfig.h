

#ifndef CLS_LOG_PRODUCER_CONFIG_H
#define CLS_LOG_PRODUCER_CONFIG_H




#import "cls_log_producer_config.h"
#import "cls_log_adaptor.h"


@interface ClsLogProducerConfig : NSObject
{
    @package ClsProducerConfig* config;
    @private NSString *endpoint;
}

- (id) initClsWithCoreInfo:(NSString *) endpoint accessKeyID:(NSString *)accessKeyID accessKeySecret:(NSString *)accessKeySecret;

- (id) initClsWithCoreInfo:(NSString *) endpoint accessKeyID:(NSString *)accessKeyID accessKeySecret:(NSString *)accessKeySecret securityToken:(NSString *)securityToken;

- (void)SetClsTopic:(NSString *) topic;

- (void)SetClsSource:(NSString *) source;

- (void)SetClsPackageLogBytes:(int) num;

- (void)SetClsPackageLogCount:(int) num;

- (void)SetClsPackageTimeout:(int) num;

- (void)SetClsMaxBufferLimit:(int) num;

- (void)SetClsSendThreadCount:(int) num;

- (void)SetClsConnectTimeoutSec:(int) num;

- (void)SetClsSendTimeoutSec:(int) num;

- (void)SetClsRetries:(int) num;

- (void)SetClsBaseRetryBackoffMs:(int) num;

- (void)SetClsMaxRetryBackoffMs:(int) num;

- (void)SetClsDestroyFlusherWaitSec:(int) num;

- (void)SetClsDestroySenderWaitSec:(int) num;

- (void)SetClsCompressType:(int) num;

- (void) SetClsEndpoint: (NSString *)endpoint;

- (NSString *)GetClsEndpoint;

- (void) SetClsAccessKeyId: (NSString *)accessKeyId;

- (void) SetClsAccessKeySecret: (NSString *) accessKeySecret;

- (void) ResetClsSecurityToken:(NSString *)securityToken;

- (void) SetPersistent:(int) persistent;

- (void) SetPersistentFilePath: (NSString *)filePath;

- (void) SetPersistentMaxLogCount: (int)max_log_count;

- (void) SetPersistentMaxFileSize: (int)file_size;

- (void) SetPersistentMaxFileCount: (int)file_count;

- (void) SetPersistentForceFlush: (int)force;

@end

#endif /* CLS_LOG_PRODUCER_CONFIG_H */
