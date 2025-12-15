#import "ClsLogSender.h"
#import "ClsLogStorage.h"
#import "CLSNetworkTool.h"
#import "ClsLogs.pbobjc.h"
#import "ClsLogModel.h"

@interface LogSender ()
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong) NSThread *workThread;
@property (nonatomic, strong) NSCondition *condition;
@property (nonatomic, assign) NSUInteger batchSize;
@property (nonatomic, strong, nonnull) ClsLogSenderConfig *config;
@end

@implementation LogSender

- (void)updateToken:(nullable NSString *)token {
    @synchronized (self) {
        // 直接修改内部 config 的 token（注意 copy 避免外部指针影响）
        _config.token = [token copy];
    }
}

+ (instancetype)sharedSender {
    static LogSender *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LogSender alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _condition = [[NSCondition alloc] init];
        _isRunning = NO;
        _batchSize = 100;
        _config = [ClsLogSenderConfig configWithEndpoint:@"" accessKeyId:@"" accessKey:@""];
    }
    return self;
}

- (void)setConfig:(ClsLogSenderConfig *)config {
    @synchronized (self) {
        _config = [config copy];
        [[ClsLogStorage sharedInstance] setMaxDatabaseSize:_config.maxMemorySize];
    }
}

- (void)start {
    @synchronized (self) {
        if (_isRunning) return;
        _isRunning = YES;
        _workThread = [[NSThread alloc] initWithTarget:self selector:@selector(workLoop) object:nil];
        _workThread.name = @"CLSLogSender";
        [_workThread start];
    }
}

- (void)stop {
    @synchronized (self) {
        if (!_isRunning) return;
        _isRunning = NO;
        [_condition signal];
        [_workThread cancel];
        _workThread = nil;
    }
}

- (void)triggerSend {
    [_condition signal];
}

- (void)workLoop {
    while (_isRunning) {
        @synchronized (self) {
            if (!_config.endpoint || !_config.accessKeyId || !_config.accessKey) {
                CLSLog(@"LogSender: config lack param");
            } else {
                // 定时触发后，循环发送日志，直到没有待发送数据
                while (YES) {
                    if (![CLSNetworkTool isNetworkAvailable]) {
                        CLSLog(@"无可用网络，取消发送");
                        break;
                    }
                    // 1. 每次查询最多 100 条待发送日志
                    NSArray *pendingLogs = [[ClsLogStorage sharedInstance] queryPendingLogs:100];
                    CLSLog(@"query send log count：%lu", (unsigned long)pendingLogs.count);
                    
                    // 2. 若没有待发送日志，退出内层循环
                    if (pendingLogs.count == 0) {
                        break;
                    }
                    
                    // 3. 同步发送当前批次日志
                    NSTimeInterval sendStartTime = [[NSDate date] timeIntervalSince1970];
                    BOOL isBatchSuccess = [self sendBatchLogs:pendingLogs];
                    NSTimeInterval sendEndTime = [[NSDate date] timeIntervalSince1970];
                    
                    if (!isBatchSuccess) {
                        // 只要失败肯定是有异常的，不需要重试
                        CLSLog(@"send %lu logs FAILED, cost %.2f s → stop current round",
                              (unsigned long)pendingLogs.count,
                              sendEndTime - sendStartTime);
                        break;
                    } else {
                        CLSLog(@"send %lu logs success, cost %.2f s",
                              (unsigned long)pendingLogs.count,
                              sendEndTime - sendStartTime);
                    }
                }
            }
        }
        
        // 4. 等待固定间隔后，再进行下一次定时检查（无论上次发送耗时多久）
        [_condition lock];
        [_condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:_config.sendLogInterval]];
        [_condition unlock];
        
        // 5. 检查线程是否被取消，若取消则退出外层循环
        if ([NSThread currentThread].isCancelled) {
            _isRunning = NO;
            break;
        }
    }
}

- (BOOL)sendBatchLogs:(NSArray<NSDictionary *> *)logs {
    if (logs.count == 0) {
        return NO;
    }
    
    // 常量定义
    const uint64_t kSingleLogMaxSize = 512 * 1024;  // 单行日志上限
    const uint64_t kBatchMaxSize = 5 * 1024 * 1024; // 聚合包上限
    
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *topicGroups = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *topicBatchSizes = [NSMutableDictionary dictionary];
    
    for (NSDictionary *log in logs) {
        Log *pbLog = log[@"log_item"];
        NSNumber *logId = log[@"id"];
        NSString *topicID = log[@"topic_id"];
        
        if (!topicID) {
            CLSLog(@"log ID %@ lack topic_id，continue", logId);
            continue;
        }
        
        // 计算单条日志大小
        uint64_t singleLogSize = [CLSNetworkTool sizeOfLogItem:pbLog];
        if (singleLogSize == 0) {
            CLSLog(@"log ID %@ calc size failed", logId);
            continue;
        }
        
        // 过滤大日志
        if (singleLogSize > kSingleLogMaxSize) {
            CLSLog(@"log ID %@ exceed 512KB（%.2f KB），discard",
                  logId, singleLogSize / 1024.0);
            [[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[logId]];
            continue;
        }
        
        // 初始化分组和大小（使用 NSNumber 包装 uint64_t）
        if (!topicGroups[topicID]) {
            topicGroups[topicID] = [NSMutableArray array];
            topicBatchSizes[topicID] = @(0ULL); // 用 @(0ULL) 包装 uint64_t 0
        }
        
        // 读取当前累计大小（从 NSNumber 中提取 uint64_t）
        uint64_t currentBatchSize = [topicBatchSizes[topicID] unsignedLongLongValue];
        uint64_t predictedSize = currentBatchSize + singleLogSize;
        
        // 检查是否超过上限
        if (predictedSize > kBatchMaxSize) {
            CLSLog(@"topic %@ The aggregated package is about to exceed 5MB (currently %.2f MB), send %lu log entries immediately",
                  topicID, currentBatchSize / 1024.0 / 1024.0,
                  (unsigned long)topicGroups[topicID].count);
            
            if (![self sendLogsGroup:topicGroups[topicID] forTopic:topicID]) {
                return NO; // 分组失败，批次整体失败
            }
            
            // 重置分组和大小（用 @(singleLogSize) 包装）
            topicGroups[topicID] = [NSMutableArray arrayWithObject:log];
            topicBatchSizes[topicID] = @(singleLogSize);
        } else {
            [topicGroups[topicID] addObject:log];
            topicBatchSizes[topicID] = @(predictedSize); // 包装为 NSNumber
        }
    }
    
    // 2. 发送剩余日志
    __block BOOL allGroupsSuccess = YES;
    [topicGroups enumerateKeysAndObjectsUsingBlock:^(NSString *topicID, NSMutableArray *groupLogs, BOOL *stop) {
        if (![self sendLogsGroup:groupLogs forTopic:topicID]) {
            allGroupsSuccess = NO;
            *stop = YES;
        }
    }];
    return allGroupsSuccess;
}

// 单独发送一个 topic 分组的日志
- (BOOL) sendLogsGroup:(NSArray<NSDictionary *> *)groupLogs forTopic:(NSString *)topicID {
    // 获取当前分组的日志ID（用于更新状态）
    NSArray<NSNumber *> *logIds = [groupLogs valueForKey:@"id"];
    if (logIds.count == 0) {
        CLSLog(@"topic %@ No valid log ID, skip sending.", topicID);
        return NO;
    }

    // 构建当前分组的 LogGroupList
    LogGroupList *logGroupList = [self buildLogGroupListFromLogItems:groupLogs];
    NSData *pbData = [logGroupList data];
    if (!pbData.length) {
        CLSLog(@"LogGroup serialization for topic %@ failed, and the recovery status is now pending transmission.", topicID);
        return NO;
    }
    
    // LZ4压缩
    ClsPostOption *option = [[ClsPostOption alloc] init];
    NSData *compressedData = [CLSNetworkTool lz4CompressData:pbData];
    if (!compressedData && option.compressType == 1) {
        CLSLog(@"LZ4 compression for topic %@ failed; send raw data instead.", topicID);
        option.compressType = 0;
        compressedData = pbData;
    }
    
    // 构建请求头和参数
    NSMutableDictionary *headers = [self buildHeadersWithCompressType:option.compressType];
    NSDictionary *params = @{@"topic_id": topicID}; // 参数中使用当前分组的 topic_id
    
    // 生成签名
    NSString *signature = [CLSNetworkTool generateSignatureWithSecretId:_config.accessKeyId
                                                            secretKey:_config.accessKey
                                                               method:@"POST"
                                                                 path:@"/structuredlog"
                                                                params:params
                                                               headers:headers
                                                                expire:300];
    // Token 头部（与 C 语言一致）
    if (_config.token) {
        headers[@"X-Cls-Token"] = _config.token; // 对应 C: put("X-Cls-Token", token)
    }
    
    [headers setObject:signature forKey:@"Authorization"];
    
    
    // 关键：使用同步请求，阻塞当前线程直到结果返回
    NSString *url = [self buildRequestUrlWithParams:params];
    CLSSendResult *result = [CLSNetworkTool sendPostRequestSyncWithUrl:url
                                                               headers:headers
                                                                 body:compressedData
                                                               option:option];
    
    [self handleSendResult:result logIds:logIds];
    return (result.statusCode == 200);
}

- (void)handleSendResult:(CLSSendResult *)result logIds:(NSArray<NSNumber *> *)logIds {
    if (logIds.count == 0) return;
    // 成功时直接删除
    if (result.statusCode == 200) {
        [[ClsLogStorage sharedInstance] deleteSentLogsWithIds:logIds];
        CLSLog(@"Send successfully, RequestID: %@, Number of messages: %lu", result.requestID, (unsigned long)logIds.count);
        return;
    }
    
    NSInteger statusCode = result.statusCode;
    
    // 需要保留日志的条件：
    // 1. 所有客户端网络错误（statusCode < 0，无需区分具体错误码）
    // 2. 服务端特定错误码（5xx、429、408、403，原逻辑保留）
    
    BOOL shouldKeepLogs = (statusCode < 0)
                        || (statusCode >= 500 && statusCode < 600)
                        || statusCode == 429
                        || statusCode == 408
                        || statusCode == 403;
    
    if (shouldKeepLogs) {
        // 保留日志（等待重试）
        CLSLog(@"Sending failed (status code: %ld), log entry %lu, error: %@",
              (long)statusCode,
              (unsigned long)logIds.count,
              result.message);
    } else {
        // 无需保留的错误（如 400 客户端参数错误、404 地址不存在等，重试无意义）
        [[ClsLogStorage sharedInstance] deleteSentLogsWithIds:logIds];
        CLSLog(@"Sending failed (status code: %ld), delete log entry %lu, error: %@",
              (long)statusCode,
              (unsigned long)logIds.count,
              result.message);
    }
}

- (LogGroupList *)buildLogGroupListFromLogItems:(NSArray<NSDictionary *> *)logs {
    LogGroupList *logGroupList = [[LogGroupList alloc] init];
    if (logs.count == 0) {
        return nil;
    }
    
    LogGroup *logGroup = [[LogGroup alloc] init];
    for (NSDictionary *logInfo in logs) {
        Log *pbLog = logInfo[@"log_item"];
        if (!pbLog) continue;
        [logGroup.logsArray addObject:pbLog];
    }
    
    if (logGroup.logsArray.count > 0) {
        [logGroupList.logGroupListArray addObject:logGroup];
    } else {
        return nil;
    }
    
    return logGroupList;
}

- (NSMutableDictionary *)buildHeadersWithCompressType:(NSInteger)compressType {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    // 与 C 语言对照：必须包含以下头部，且 key 大小写需匹配（最终会转为小写）
    headers[@"Host"] = _config.endpoint; // 对应 C: put(&httpHeader, "Host", endpoint)
    headers[@"Content-Type"] = @"application/x-protobuf"; // 对应 C: put("Content-Type", ...)
    headers[@"User-Agent"] = @"tencent-log-sdk-ios v2.0.0"; // 完全一致
    headers[@"x-cls-trace-id"] = [[NSUUID UUID] UUIDString]; // 对应 C: x-cls-trace-id
    headers[@"x-cls-add-source"] = @"1";
    
    // 压缩头部（与 C 语言一致：仅当压缩时添加）
    if (compressType == 1) {
        headers[@"x-cls-compress-type"] = @"lz4"; // 对应 C: put("x-cls-compress-type", "lz4")
    }
    
    return headers;
}

- (NSString *)buildRequestUrlWithParams:(NSDictionary *)params {
    NSString *operation = @"/structuredlog";
    NSString *queryString = [self generateQueryStringWithParams:params];
    return [NSString stringWithFormat:@"https://%@%@%@",
            _config.endpoint, operation, queryString.length ? [NSString stringWithFormat:@"?%@", queryString] : @""];
}

- (NSString *)generateQueryStringWithParams:(NSDictionary *)params {
    NSMutableArray *paramStrs = [NSMutableArray array];
    for (NSString *key in [params.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [paramStrs addObject:[NSString stringWithFormat:@"%@=%@",
                              [self urlEncode:key], [self urlEncode:params[key]]]];
    }
    return [paramStrs componentsJoinedByString:@"&"];
}

- (NSString *)urlEncode:(NSString *)str {
    return [str stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
}

@end

@interface ClsLogSenderConfig () {
    uint64_t _sendLogInterval;
    uint64_t _maxMemorySize;
}
@end


@implementation ClsLogSenderConfig

static const uint64_t kMinSendInterval = 1;
static const uint64_t kDefaultSendInterval = 5;

static const uint64_t kMinMemorySize = 16*1024 * 1024;
static const uint64_t kDefaultMemorySize = 32 * 1024 * 1024;

+ (instancetype)configWithEndpoint:(NSString *)endpoint
                        accessKeyId:(NSString *)accessKeyId
                          accessKey:(NSString *)accessKey {
    ClsLogSenderConfig *config = [[self alloc] init];
    // 服务器配置
    config.endpoint = [endpoint copy];
    config.accessKeyId = [accessKeyId copy];
    config.accessKey = [accessKey copy];
    return config;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _maxMemorySize = kDefaultMemorySize;
        _sendLogInterval = kDefaultSendInterval;
    }
    return self;
}

#pragma mark - NSCopying 协议实现（核心修复）
- (id)copyWithZone:(NSZone *)zone {
    ClsLogSenderConfig *copyConfig = [[[self class] allocWithZone:zone] init];
    if (copyConfig) {
        copyConfig.endpoint = [self.endpoint copy];
        copyConfig.accessKeyId = [self.accessKeyId copy];
        copyConfig.accessKey = [self.accessKey copy];
        copyConfig.token = [self.token copy]; // 复制token（默认nil也会正确复制）
        copyConfig.maxMemorySize = self.maxMemorySize; // 复制最大size默认值
        copyConfig.sendLogInterval = self.sendLogInterval;
    }
    return copyConfig;
}

#pragma mark - sendLogInterval 校验（发送间隔，单位：秒）
- (void)setSendLogInterval:(uint64_t)sendLogInterval {
    if (sendLogInterval < kMinSendInterval) {
        _sendLogInterval = kMinSendInterval;
    }else{
        _sendLogInterval = sendLogInterval;
    }
}

- (uint64_t)sendLogInterval {
    return _sendLogInterval;
}

#pragma mark - maxMemorySize 校验（内存上限，单位：字节）
- (void)setMaxMemorySize:(uint64_t)maxMemorySize {
    if (maxMemorySize < kMinMemorySize) {
        // 仅使用 kMinMemorySize 的值，不修改它
        _maxMemorySize = kMinMemorySize;
    } else {
        _maxMemorySize = maxMemorySize;
    }
}

- (uint64_t)maxMemorySize {
    return _maxMemorySize;
}

@end
