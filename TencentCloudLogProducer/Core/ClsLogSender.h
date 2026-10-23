#import <Foundation/Foundation.h>


FOUNDATION_EXPORT NSString * _Nonnull const kCLSErrorInvalidUin;


@interface ClsLogSenderConfig : NSObject <NSCopying>

// 服务器配置（原有参数）
@property (nonatomic, copy, nonnull) NSString *endpoint;       // 接入域名（如 ap-guangzhou.cls.tencentcs.com）
@property (nonatomic, copy, nonnull) NSString *accessKeyId;    // 访问密钥ID
@property (nonatomic, copy, nonnull) NSString *accessKey;      // 访问密钥
@property (nonatomic, copy, nullable) NSString *token;         // 临时令牌（可选）

@property (nonatomic, copy, nullable) NSString *uin;

@property (nonatomic, assign) uint64_t maxMemorySize;
@property (nonatomic, assign) uint64_t sendLogInterval;


// 快速初始化（必传核心服务器参数，其他用默认值）
+ (nonnull instancetype)configWithEndpoint:(nonnull NSString *)endpoint
                              accessKeyId:(nonnull NSString *)accessKeyId
                                accessKey:(nonnull NSString *)accessKey;

@end


@interface LogSender : NSObject

+ (instancetype)sharedSender;

+ (BOOL)isWeakAuthConfig:(nonnull ClsLogSenderConfig *)config;

+ (BOOL)isUinValid:(nullable NSString *)uin;

+ (void)setLogEnabled:(BOOL)enabled;

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
 使用约束：
 - start / stop 必须在同一线程串行调用（不要跨线程交错）；SDK 内部使用配置锁保护状态，
   但在跨线程交错 start/stop 的中间态，可能出现"旧线程尚未完全退出而新线程已启动"的瞬时窗口；
   #9 修复已消除两线程并发上传同一批日志的风险，但不保证 stop 后立即 start 一定抢到最新 config 快照。
 - stop 立即返回；在途的单个请求继续执行完毕，不会被打断；外部不应依赖"stop 返回时所有发送已结束"。
 */
- (void)start;
- (void)stop;

/**
 手动触发一次日志发送（用于网络恢复后立即重试）
 */
- (void)triggerSend;

@end
