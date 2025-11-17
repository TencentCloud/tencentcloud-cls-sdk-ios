#import <Foundation/Foundation.h>



@interface ClsLogSenderConfig : NSObject <NSCopying>

// 服务器配置（原有参数）
@property (nonatomic, copy, nonnull) NSString *endpoint;       // 接入域名（如 ap-guangzhou.cls.tencentcs.com）
@property (nonatomic, copy, nonnull) NSString *accessKeyId;    // 访问密钥ID
@property (nonatomic, copy, nonnull) NSString *accessKey;      // 访问密钥
@property (nonatomic, copy, nullable) NSString *token;         // 临时令牌（可选）
@property (nonatomic, assign) uint64_t maxMemorySize;
@property (nonatomic, assign) uint64_t sendLogInterval;


// 快速初始化（必传核心服务器参数，其他用默认值）
+ (nonnull instancetype)configWithEndpoint:(nonnull NSString *)endpoint
                              accessKeyId:(nonnull NSString *)accessKeyId
                                accessKey:(nonnull NSString *)accessKey;

@end


@interface LogSender : NSObject

+ (instancetype)sharedSender;

/**
 设置服务端配置（新增主题ID参数）
 */
- (void)setConfig:(nonnull ClsLogSenderConfig *)config;
//- (void)setServerConfigWithEndpoint:(NSString *)endpoint
//                        accessKeyId:(NSString *)accessKeyId
//                          accessKey:(NSString *)accessKey
//                              token:(nullable NSString *)token;

/**
 更新临时令牌（token）
 @param token 新的临时令牌，nil 表示清除
 */
- (void)updateToken:(nullable NSString *)token;

/**
 启动/停止发送线程
 */
- (void)start;
- (void)stop;

/**
 手动触发一次日志发送（用于网络恢复后立即重试）
 */
- (void)triggerSend;

@end
