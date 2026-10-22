#import "ClsLogSender.h"
#import "ClsLogStorage.h"
#import "CLSNetworkTool.h"
#import "ClsLogs.pbobjc.h"
#import "ClsLogModel.h"

NSString * const kCLSErrorInvalidUin = @"InvalidUin";

@interface LogSender ()
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong) NSThread *workThread;
@property (nonatomic, strong) NSCondition *condition;
@property (nonatomic, strong) NSLock *sendLock;
@property (nonatomic, assign) NSUInteger batchSize;
@property (nonatomic, strong, nonnull) ClsLogSenderConfig *config;
@end

@implementation LogSender

+ (BOOL)isWeakAuthConfig:(ClsLogSenderConfig *)config {
    if (!config) return NO;
    return (config.accessKeyId.length == 0) || (config.accessKey.length == 0);
}

+ (BOOL)isUinValid:(NSString *)uin {
    if (uin.length == 0) return NO;
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [uin rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

+ (void)setLogEnabled:(BOOL)enabled {
    CLSSetLogEnabled(enabled);
}

- (void)updateToken:(nullable NSString *)token {
    @synchronized (self) {
        if ([LogSender isWeakAuthConfig:_config]) {
            CLSLog(@"[weak-auth] updateToken ignored under weak auth mode; uin=%@",
                   _config.uin ?: @"");
            return;
        }
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
        _sendLock = [[NSLock alloc] init];
        _isRunning = NO;
        _batchSize = 100;
        _config = [ClsLogSenderConfig configWithEndpoint:@"" accessKeyId:@"" accessKey:@""];
    }
    return self;
}

- (ClsLogSenderConfig *)configSnapshot {
    @synchronized (self) {
        return [_config copy];
    }
}

- (BOOL)isConfigValid:(ClsLogSenderConfig *)cfg {
    if (cfg.endpoint.length == 0) return NO;
    BOOL strongAuthOk = (cfg.accessKeyId.length > 0) && (cfg.accessKey.length > 0);
    BOOL weakAuthOk = [LogSender isWeakAuthConfig:cfg] && [LogSender isUinValid:cfg.uin];
    return strongAuthOk || weakAuthOk;
}

- (void)setConfig:(ClsLogSenderConfig *)config {
    @synchronized (self) {
        _config = [config copy];
        [[ClsLogStorage sharedInstance] setMaxDatabaseSize:_config.maxMemorySize];

        BOOL isWeak = [LogSender isWeakAuthConfig:_config];
        BOOL hasUin = (_config.uin.length > 0);
        if (!isWeak) {
            if (hasUin) {
                CLSLog(@"[weak-auth] AK/SK present, 'uin' is ignored");
            }
        } else {
            if (!hasUin) {
                CLSLog(@"[ERROR] missing credentials: configure AccessKeyId/AccessKey, "
                       @"or configure 'uin' for weak-auth mode");
            } else if (![LogSender isUinValid:_config.uin]) {
                CLSLog(@"[ERROR] %@: 'uin' must be a non-empty numeric string, got: '%@'",
                       kCLSErrorInvalidUin, _config.uin);
            } else {
                CLSLog(@"[weak-auth] weak-auth mode enabled, uin=%@", _config.uin);
            }
        }
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
    NSThread *thread = nil;
    @synchronized (self) {
        if (!_isRunning) return;
        _isRunning = NO;
        thread = _workThread;
        _workThread = nil;
    }
    [thread cancel];
    [_condition lock];
    [_condition signal];
    [_condition unlock];
}

- (void)triggerSend {
    [_condition lock];
    [_condition signal];
    [_condition unlock];
}

- (void)workLoop {
    NSThread *me = [NSThread currentThread];
    while (!me.isCancelled) {
        @autoreleasepool {
            [_sendLock lock];
            [self sendAllPendingOnThread:me];
            [_sendLock unlock];

            uint64_t interval = [self configSnapshot].sendLogInterval;
            [_condition lock];
            if (!me.isCancelled) {
                [_condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:interval]];
            }
            [_condition unlock];
        }
    }
    // #9 修复 R-1：不再在此写 `_isRunning = NO`。
    // `_isRunning` 仅由 `start/stop` 在配置锁内修改；
    // 若 workLoop 退出时又写一次，会与"stop → 紧接着 start"竞态，
    // 导致 oldThread 退出覆盖了 start 刚置的 YES，start 判断失效后再调用会创建第二个 worker。
}

- (void)sendAllPendingOnThread:(NSThread *)me {
    while (!me.isCancelled) {
        @autoreleasepool {
            ClsLogSenderConfig *cfg = [self configSnapshot];
            if (![self isConfigValid:cfg]) {
                CLSLog(@"LogSender: config invalid, skip");
                return;
            }
            if (![CLSNetworkTool isNetworkAvailable]) {
                CLSLog(@"无可用网络，取消发送");
                return;
            }
            NSArray *pendingLogs = [[ClsLogStorage sharedInstance] queryPendingLogs:100];
            if (pendingLogs.count == 0) return;
            if (![self sendBatchLogs:pendingLogs config:cfg]) return;
        }
    }
}

- (BOOL)sendBatchLogs:(NSArray<NSDictionary *> *)logs config:(ClsLogSenderConfig *)cfg {
    if (logs.count == 0) {
        return NO;
    }

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

        uint64_t singleLogSize = [CLSNetworkTool sizeOfLogItem:pbLog];
        if (singleLogSize == 0) {
            CLSLog(@"log ID %@ calc size failed", logId);
            continue;
        }

        // #14 兜底：writeLog 已拦截超限日志，这里仅为升级前已入库的历史超大日志
        if (singleLogSize > kCLSMaxSingleLogBytes) {
            CLSLog(@"log ID %@ exceed 512KB（%.2f KB），discard",
                  logId, singleLogSize / 1024.0);
            (void)[[ClsLogStorage sharedInstance] deleteSentLogsWithIds:@[logId]];
            continue;
        }

        if (!topicGroups[topicID]) {
            topicGroups[topicID] = [NSMutableArray array];
            topicBatchSizes[topicID] = @(0ULL);
        }

        uint64_t currentBatchSize = [topicBatchSizes[topicID] unsignedLongLongValue];
        uint64_t predictedSize = currentBatchSize + singleLogSize;

        if (predictedSize > kBatchMaxSize) {
            if (![self sendLogsGroup:topicGroups[topicID] forTopic:topicID config:cfg]) {
                return NO;
            }
            topicGroups[topicID] = [NSMutableArray arrayWithObject:log];
            topicBatchSizes[topicID] = @(singleLogSize);
        } else {
            [topicGroups[topicID] addObject:log];
            topicBatchSizes[topicID] = @(predictedSize);
        }
    }

    __block BOOL allGroupsSuccess = YES;
    [topicGroups enumerateKeysAndObjectsUsingBlock:^(NSString *topicID, NSMutableArray *groupLogs, BOOL *stop) {
        if (![self sendLogsGroup:groupLogs forTopic:topicID config:cfg]) {
            allGroupsSuccess = NO;
            *stop = YES;
        }
    }];
    return allGroupsSuccess;
}

- (BOOL) sendLogsGroup:(NSArray<NSDictionary *> *)groupLogs forTopic:(NSString *)topicID {
    return [self sendLogsGroup:groupLogs forTopic:topicID config:[self configSnapshot]];
}

- (BOOL) sendLogsGroup:(NSArray<NSDictionary *> *)groupLogs forTopic:(NSString *)topicID config:(ClsLogSenderConfig *)cfg {
    NSArray<NSNumber *> *logIds = [groupLogs valueForKey:@"id"];
    if (logIds.count == 0) {
        CLSLog(@"topic %@ No valid log ID, skip sending.", topicID);
        return NO;
    }

    LogGroupList *logGroupList = [self buildLogGroupListFromLogItems:groupLogs];
    NSData *pbData = [logGroupList data];
    if (!pbData.length) {
        CLSLog(@"LogGroup serialization for topic %@ failed", topicID);
        return NO;
    }

    ClsPostOption *option = [[ClsPostOption alloc] init];
    NSData *compressedData = [CLSNetworkTool lz4CompressData:pbData];
    if (!compressedData && option.compressType == 1) {
        CLSLog(@"LZ4 compression for topic %@ failed; send raw data instead.", topicID);
        option.compressType = 0;
        compressedData = pbData;
    }

    NSMutableDictionary *headers = [self buildHeadersWithCompressType:option.compressType config:cfg];
    NSDictionary *params = @{@"topic_id": topicID};

    if ([LogSender isWeakAuthConfig:cfg]) {
        headers[@"x-cls-auth-mode"] = @"weak";
        headers[@"X-CLS-Uin"] = cfg.uin ?: @"";
    } else {
        NSString *signature = [CLSNetworkTool generateSignatureWithSecretId:cfg.accessKeyId
                                                                  secretKey:cfg.accessKey
                                                                     method:@"POST"
                                                                       path:@"/structuredlog"
                                                                     params:params
                                                                    headers:headers
                                                                     expire:300];
        if (cfg.token.length > 0) {
            headers[@"X-Cls-Token"] = cfg.token;
        }
        [headers setObject:signature forKey:@"Authorization"];
    }

    NSString *url = [self buildRequestUrlWithParams:params config:cfg];
    CLSSendResult *result = [CLSNetworkTool sendPostRequestSyncWithUrl:url
                                                               headers:headers
                                                                 body:compressedData
                                                               option:option];

    return [self handleSendResult:result logIds:logIds];
}

- (BOOL)handleSendResult:(CLSSendResult *)result logIds:(NSArray<NSNumber *> *)logIds {
    if (logIds.count == 0) return NO;
    if (result.statusCode == 200) {
        BOOL deleted = [[ClsLogStorage sharedInstance] deleteSentLogsWithIds:logIds];
        if (!deleted) {
            CLSLog(@"[CLS] DELETE failed after HTTP 200, stop current round to prevent duplicate storm, RequestID: %@",
                   result.requestID);
            return NO;
        }
        CLSLog(@"Send successfully, RequestID: %@, Number of messages: %lu",
               result.requestID, (unsigned long)logIds.count);
        return YES;
    }

    NSInteger statusCode = result.statusCode;

    // #22 修复：非 NSURLErrorDomain 的正数网络错误码（如 CFNetwork 自定义错误）也应视为"保留"
    BOOL isNetworkError = (statusCode < 0);
    // 服务端临时性错误
    BOOL isTransientServerError = (statusCode >= 500 && statusCode < 600)
                                || statusCode == 429
                                || statusCode == 408
                                || statusCode == 403;
    // 异常：非 HTTP 2xx/3xx/4xx 的奇怪值（例如 CFNetwork 的正数自定义码），一律保留
    BOOL isOutsideHttpRange = (statusCode > 0 && (statusCode < 100 || statusCode > 599));

    BOOL shouldKeepLogs = isNetworkError || isTransientServerError || isOutsideHttpRange;

    if (shouldKeepLogs) {
        CLSLog(@"Sending failed (status code: %ld), keep log entry %lu, error: %@",
              (long)statusCode, (unsigned long)logIds.count, result.message);
    } else {
        (void)[[ClsLogStorage sharedInstance] deleteSentLogsWithIds:logIds];
        CLSLog(@"Sending failed (status code: %ld), delete log entry %lu, error: %@",
              (long)statusCode, (unsigned long)logIds.count, result.message);
    }
    return NO;
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

- (NSMutableDictionary *)buildHeadersWithCompressType:(NSInteger)compressType config:(ClsLogSenderConfig *)cfg {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    headers[@"Host"] = cfg.endpoint;
    headers[@"Content-Type"] = @"application/x-protobuf";
    headers[@"User-Agent"] = @"tencent-log-sdk-ios v3.3.0";
    headers[@"x-cls-trace-id"] = [[NSUUID UUID] UUIDString];
    headers[@"x-cls-add-source"] = @"1";

    if (compressType == 1) {
        headers[@"x-cls-compress-type"] = @"lz4";
    }

    return headers;
}

- (NSString *)buildRequestUrlWithParams:(NSDictionary *)params config:(ClsLogSenderConfig *)cfg {
    NSString *operation = @"/structuredlog";
    NSString *queryString = [self generateQueryStringWithParams:params];
    return [NSString stringWithFormat:@"https://%@%@%@",
            cfg.endpoint, operation, queryString.length ? [NSString stringWithFormat:@"?%@", queryString] : @""];
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
        copyConfig.uin = [self.uin copy];
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
