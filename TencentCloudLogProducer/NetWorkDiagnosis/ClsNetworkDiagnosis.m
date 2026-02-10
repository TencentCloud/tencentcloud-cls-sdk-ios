//
//  ClsNetworkDiagnosis.m
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import "ClsNetworkDiagnosis.h"
#import "CLSNetworkUtils.h"
#import "CLSHttpingV2.h"
#import "CLSTcpingV2.h"
#import "CLSPingV2.h"
#import "CLSDnsping.h"
#import "CLSMtrping.h"

@implementation CLSRequest

- (instancetype)init {
    self = [super init]; // 1. 调用父类(NSObject)的初始化方法[3,5](@ref)
    if (self) { // 2. 检查初始化是否成功[3,6](@ref)
        // 3. 为属性设置默认值，避免nil带来的潜在问题
        _domain = @"";
        _appKey = @"";
        _detectEx = @{};
        
        // 核心参数默认值
        _size = 64;         // 包大小默认 64 字节 (范围: 8-1024)
        _maxTimes = 1;      // 探测次数默认 1 次 (范围: 1-100)
        _timeout = 5000;    // 单次探测超时时间默认 5000 毫秒 (范围: 0 < timeout ≤ 300000)
        
        _pageName = @"";
        _enableMultiplePortsDetect = NO;
    }
    return self; // 4. 返回初始化后的对象[5](@ref)
}

@end

@implementation CLSHttpRequest
// 使用从 CLSRequest 继承的 init 方法
- (instancetype)init {
    self = [super init]; // 1. 先调用父类(CLSRequest)的init方法[1,4](@ref)
    if (self) {
        // 2. 初始化子类自己的属性
        _enableSSLVerification = YES;
        self.timeout = 30000;  // HTTP默认超时时间: 30000 ms (30秒)
    }
    return self;
}
@end

@implementation CLSPingRequest
// 使用从 CLSRequest 继承的 init 方法
- (instancetype)init {
    self = [super init]; // 1. 先调用父类(CLSRequest)的init方法[1,4](@ref)
    if (self) {
        // 2. 初始化子类自己的属性
        _interval = 200;
        _prefer = -1;  // 默认自动检测
        self.timeout = 2000;  // Ping默认超时时间: 2000 ms (2秒)
    }
    return self;
}
@end

@implementation CLSTcpRequest

- (instancetype)init {
    self = [super init]; // 1. 先调用父类(CLSRequest)的init方法[1,4](@ref)
    if (self) {
        // 2. 初始化子类自己的属性
        _port = 0;
        self.timeout = 2000;  // TCP默认超时时间: 2000 ms (2秒)
    }
    return self;
}

@end

@implementation CLSDnsRequest

- (instancetype)init {
    self = [super init]; // 1. 先调用父类(CLSRequest)的init方法[1,4](@ref)
    if (self) {
        // 2. 初始化子类自己的属性
        _nameServer = @"";
        _prefer = -1;  // 默认自动检测
        self.timeout = 5000;  // DNS默认超时时间: 5000 ms (5秒)
    }
    return self;
}

@end

@implementation CLSMtrRequest
- (instancetype)init {
    self = [super init]; // 1. 先调用父类(CLSRequest)的init方法[1,4](@ref)
    if (self) {
        // 2. 初始化子类自己的属性
        _maxTTL = 64;
        _protocol = @"icmp";
        _prefer = -1;  // 默认自动检测
        self.timeout = 1500;  // MTR默认超时时间: 1500 ms
    }
    return self;
}
// 使用从 CLSRequest 继承的 init 方法
@end

@interface ClsNetworkDiagnosis ()
@property(nonatomic, assign) long index;
@property(nonatomic, strong) NSLock *lock;

@property(nonatomic, strong) ClsLogSenderConfig *config;
@property(nonatomic, strong) NSMutableArray *callbacks;

- (NSString *) generateId;
@end

@implementation CLSBaseFields
// 使用从 CLSRequest 继承的 init 方法
@end

@interface ClsNetworkDiagnosis ()
/// 内部持有的LogSender（仅初始化一次）
@property (nonatomic, strong) LogSender *internalLogSender;
/// 标记是否已配置LogSender（防止重复初始化）
@property (nonatomic, assign, getter=isLogSenderConfigured) BOOL logSenderConfigured;
@property (nonatomic, copy) NSString *topicId;
@property (nonatomic, copy) NSString *netToken;

// ===== netToken 解析结果缓存（提前解析，避免重复解析）=====
@property (nonatomic, copy) NSString *cachedNetworkAppId;
@property (nonatomic, copy) NSString *cachedAppKey;
@property (nonatomic, copy) NSString *cachedUin;
@property (nonatomic, copy) NSString *cachedRegion;
@property (nonatomic, copy) NSString *cachedTopicId;
@property (nonatomic, assign) BOOL isNetTokenParsed; // 标记是否已解析 netToken

// ===== 全局 userEx（所有探测共享）=====
@property (nonatomic, strong) NSDictionary<NSString*, NSString*> *globalUserEx;
@end

@implementation ClsNetworkDiagnosis
+ (instancetype)sharedInstance {
    static ClsNetworkDiagnosis *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    // dispatch_once 保证全局仅初始化一次
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[super allocWithZone:NULL] init];
        // 初始化默认状态
        _sharedInstance.logSenderConfigured = NO;
        _sharedInstance.internalLogSender = nil;
        _sharedInstance.topicId = @"";
        _sharedInstance.netToken = @"";
        _sharedInstance.isNetTokenParsed = NO;
        _sharedInstance.globalUserEx = @{};  // 默认空字典
        
    });
    return _sharedInstance;
}

#pragma mark - 禁止外部初始化
+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    return [self sharedInstance];
}

#pragma mark - 全局 userEx 设置
/// 设置全局 userEx，后续所有探测上报时会携带此字段
- (void)setUserEx:(NSDictionary<NSString*, NSString*> *)userEx {
    @synchronized (self) {
        _globalUserEx = userEx ?: @{};  // nil 安全处理
        NSLog(@"[ClsNetworkDiagnosis] 全局 userEx 已更新: %@", _globalUserEx);
    }
}

/// 获取全局 userEx（线程安全）
- (NSDictionary<NSString*, NSString*> *)getUserEx {
    @synchronized (self) {
        return [_globalUserEx copy];  // 返回副本，避免外部修改
    }
}

#pragma mark - LogSender 配置（仅首次调用有效）
/// 初始化LogSender，topicId和netToken二选一，仅首次调用生效
/// @param config 基础配置
/// @param topicId 主题ID（与netToken二选一）
/// @param netToken 网络令牌（与topicId二选一）
- (void)setupLogSenderWithConfig:(ClsLogSenderConfig *)config
                         topicId:(NSString * _Nullable)topicId{
    if (topicId.length == 0) {
        NSLog(@"错误：topicId不能为空");
        return;
    }
    // 复用核心逻辑
    [self innerSetupLogSenderWithConfig:config topicId:topicId netToken:nil];
}

- (void)setupLogSenderWithConfig:(ClsLogSenderConfig *)config
                        netToken:(NSString * _Nullable)netToken{
    if (netToken.length == 0) {
        NSLog(@"错误：netToken不能为空");
        return;
    }
    [self innerSetupLogSenderWithConfig:config topicId:nil netToken:netToken];
}
- (void)innerSetupLogSenderWithConfig:(ClsLogSenderConfig *)config
                         topicId:(NSString * _Nullable)topicId
                        netToken:(NSString * _Nullable)netToken {
    // 加锁保证线程安全，且仅首次调用生效
    @synchronized (self) {
        if (self.isLogSenderConfigured) {
            NSLog(@"LogSender已配置，无需重复初始化");
            return;
        }
        
        // 校验二选一参数（至少传入一个）
        if (topicId.length == 0 && netToken.length == 0) {
            NSLog(@"错误：topicId和netToken必须传入至少一个");
            return; // 或抛出异常，根据业务需求处理
        }
        
        // 1. 初始化LogSender（全局唯一实例）
        self.config = [config copy];
        self.internalLogSender = [LogSender sharedSender];
        [self.internalLogSender setConfig:config];
        
        // 2. 设置二选一参数（根据实际需求将参数传递给LogSender）
        if (topicId.length > 0) {
            _topicId = topicId;
            _isNetTokenParsed = NO; // 使用 topicId，不解析 netToken
        } else {
            _netToken = netToken;
            // 【优化】提前解析 netToken，缓存解析结果
            [self parseAndCacheNetToken:netToken];
        }
        
        // 3. 启动LogSender
        [self.internalLogSender start];
        
        // 4. 标记已配置，禁止重复初始化
        self.logSenderConfigured = YES;
        NSLog(@"LogSender初始化完成（全局唯一），%@生效", topicId.length > 0 ? @"topicId" : @"netToken");
    }
}

#pragma mark - netToken 解析与缓存（私有方法）

/// 解析 netToken 并缓存结果（仅在初始化时调用一次）
/// @param netToken 网络令牌
- (void)parseAndCacheNetToken:(NSString *)netToken {
    if (netToken.length == 0) {
        NSLog(@"[ClsNetworkDiagnosis] netToken 为空，无法解析");
        _isNetTokenParsed = NO;
        return;
    }
    
    // 调用工具类解析 netToken
    NSDictionary *tokenInfo = [CLSNetworkUtils parseNetToken:netToken];
    
    if (tokenInfo.count == 0) {
        NSLog(@"[ClsNetworkDiagnosis] netToken 解析失败，token: %@", netToken);
        _isNetTokenParsed = NO;
        return;
    }
    
    // 缓存解析结果
    _cachedNetworkAppId = tokenInfo[@"networkAppId"] ?: @"";
    _cachedAppKey = tokenInfo[@"appKey"] ?: @"";
    _cachedUin = tokenInfo[@"uin"] ?: @"";
    _cachedRegion = tokenInfo[@"region"] ?: @"";
    _cachedTopicId = tokenInfo[@"topic_id"] ?: @"";
    _isNetTokenParsed = YES;
    
    NSLog(@"[ClsNetworkDiagnosis] netToken 解析成功并缓存，networkAppId=%@, topicId=%@", 
          _cachedNetworkAppId, _cachedTopicId);
}

/// 填充探测器的 token 信息（使用缓存的解析结果）
/// @param detector 探测器实例（CLSBaseFields 子类）
- (void)fillTokenInfoToDetector:(CLSBaseFields *)detector {
    if (!detector) {
        return;
    }
    
    // 使用 topicId 模式
    if (_topicId.length > 0) {
        detector.topicId = _topicId;
        return;
    }
    
    // 使用 netToken 模式
    if (_isNetTokenParsed) {
        // 使用缓存的解析结果，避免重复解析
        detector.networkAppId = _cachedNetworkAppId;
        detector.appKey = _cachedAppKey;
        detector.uin = _cachedUin;
        detector.region = _cachedRegion;
        detector.topicId = _cachedTopicId;
    } else {
        // 如果缓存无效，尝试重新解析（兜底逻辑）
        NSLog(@"[ClsNetworkDiagnosis] 警告：netToken 未解析或解析失败，尝试重新解析");
        [self parseAndCacheNetToken:_netToken];
        
        if (_isNetTokenParsed) {
            detector.networkAppId = _cachedNetworkAppId;
            detector.appKey = _cachedAppKey;
            detector.uin = _cachedUin;
            detector.region = _cachedRegion;
            detector.topicId = _cachedTopicId;
        } else {
            NSLog(@"[ClsNetworkDiagnosis] 错误：netToken 解析失败，无法填充探测器信息");
        }
    }
}

// MARK: - 工具方法：空值/空字符串校验（私有）
- (BOOL)isStringEmpty:(NSString *)str {
    if (str == nil) return YES;
    // 可选：过滤空白字符（空格/换行/制表符）
    NSString *trimmedStr = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [trimmedStr isEqualToString:@""];
}

// MARK: - 核心封装：所有参数校验逻辑（对外可暴露，也可私有）
- (BOOL)validateParamsWithRequest:(NSString *)domain{
    BOOL isSelfTopicIdEmpty = [self isStringEmpty:_topicId];
    BOOL isSelfNetTokenEmpty = [self isStringEmpty:_netToken];
    BOOL isSelfEndpointEmpty = [self isStringEmpty:_config.endpoint];
    BOOL isReqDomainEmpty = [self isStringEmpty:domain];
    
    // 2.1 topicId和netToken同时为空
    if (isSelfTopicIdEmpty && isSelfNetTokenEmpty) {
        return NO;
    }
    
    // 2.2 config.endpoint为空
    if (isSelfEndpointEmpty) {
        return NO;
    }
    
    // 3.2 request.domain为空
    if (isReqDomainEmpty) {
        return NO;
    }

    return YES;
}

/*****协议升级以下是v2接口****/
- (void) httpingv2:(CLSHttpRequest *) request complate:(CompleteCallback)complate{
    if (![self validateParamsWithRequest:request.domain]) {
        NSLog(@"param error");
        return;
    }
    
    CLSMultiInterfaceHttping *httping = [[CLSMultiInterfaceHttping alloc] initWithRequest:request];
    // 使用统一的填充方法（基于缓存的解析结果）
    [self fillTokenInfoToDetector:httping];
    httping.endPoint = _config.endpoint;
    [httping start:complate];
}

- (void) tcpPingv2:(CLSTcpRequest *) request complate:(CompleteCallback)complate{
    if (![self validateParamsWithRequest:request.domain]) {
        NSLog(@"param error");
        return;
    }
    
    CLSMultiInterfaceTcping *tcpPing = [[CLSMultiInterfaceTcping alloc] initWithRequest:request];
    // 使用统一的填充方法（基于缓存的解析结果）
    [self fillTokenInfoToDetector:tcpPing];
    tcpPing.endPoint = _config.endpoint;
    [tcpPing start:complate];
}
- (void) pingv2:(CLSPingRequest *) request complate:(CompleteCallback)complate{
    if (![self validateParamsWithRequest:request.domain]) {
        NSLog(@"param error");
        return;
    }
    
    CLSMultiInterfacePing *ping = [[CLSMultiInterfacePing alloc] initWithRequest:request];
    // 使用统一的填充方法（基于缓存的解析结果）
    [self fillTokenInfoToDetector:ping];
    ping.endPoint = _config.endpoint;
    [ping start:complate];
}

- (void) dns:(CLSDnsRequest *) request complate:(CompleteCallback)complate{
    if (![self validateParamsWithRequest:request.domain]) {
        NSLog(@"param error");
        return;
    }
    
    CLSMultiInterfaceDns *dns = [[CLSMultiInterfaceDns alloc] initWithRequest:request];
    // 使用统一的填充方法（基于缓存的解析结果）
    [self fillTokenInfoToDetector:dns];
    dns.endPoint = _config.endpoint;
    [dns start:complate];
}
- (void) mtr:(CLSMtrRequest *) request complate:(CompleteCallback)complate{
    if (![self validateParamsWithRequest:request.domain]) {
        NSLog(@"param error");
        return;
    }
    
    CLSMultiInterfaceMtr *mtr = [[CLSMultiInterfaceMtr alloc] initWithRequest:request];
    // 使用统一的填充方法（基于缓存的解析结果）
    [self fillTokenInfoToDetector:mtr];
    mtr.endPoint = _config.endpoint;
    [mtr start:complate];
}
@end
