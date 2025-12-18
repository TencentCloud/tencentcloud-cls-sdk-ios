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
        // 3. 为属性设置默认空值，避免nil带来的潜在问题
        _domain = @"";
        _appKey = @"";
        _userEx = @{};
        _detectEx = @{};
        _size = 64;
        _maxTimes = 10;
        _timeout = 60*1000;
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
        // 2. 初始化子类自己的属性，port默认为0是一个合理的选择
        _enableSSLVerification = YES;
    }
    return self;
}
@end

@implementation CLSPingRequest
// 使用从 CLSRequest 继承的 init 方法
- (instancetype)init {
    self = [super init]; // 1. 先调用父类(CLSRequest)的init方法[1,4](@ref)
    if (self) {
        // 2. 初始化子类自己的属性，port默认为0是一个合理的选择
        _interval = 200;
    }
    return self;
}
@end

@implementation CLSTcpRequest

- (instancetype)init {
    self = [super init]; // 1. 先调用父类(CLSRequest)的init方法[1,4](@ref)
    if (self) {
        // 2. 初始化子类自己的属性，port默认为0是一个合理的选择
        _port = 0;
    }
    return self;
}

@end

@implementation CLSDnsRequest

- (instancetype)init {
    self = [super init]; // 1. 先调用父类(CLSRequest)的init方法[1,4](@ref)
    if (self) {
        // 2. 初始化子类自己的属性，设置为空字符串
        _nameServer = @"";
    }
    return self;
}

@end

@implementation CLSMtrRequest
- (instancetype)init {
    self = [super init]; // 1. 先调用父类(CLSRequest)的init方法[1,4](@ref)
    if (self) {
        // 2. 初始化子类自己的属性，设置为空字符串
        _maxTTL = 64;
        _protocol = @"icmp";
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
        
    });
    return _sharedInstance;
}

#pragma mark - 禁止外部初始化
+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    return [self sharedInstance];
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
        } else {
            _netToken = netToken;
        }
        
        // 3. 启动LogSender
        [self.internalLogSender start];
        
        // 4. 标记已配置，禁止重复初始化
        self.logSenderConfigured = YES;
        NSLog(@"LogSender初始化完成（全局唯一），%@生效", topicId.length > 0 ? @"topicId" : @"netToken");
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
    if(_netToken != nil && _netToken.length != 0){
        NSDictionary *tokenInfo = [CLSNetworkUtils parseNetToken:_netToken];
        if (tokenInfo.count == 0 && _topicId == nil) {
            NSLog(@"token parse failed，token:%@", _netToken);
            return;
        }
        httping.networkAppId = tokenInfo[@"networkAppId"];
        httping.appKey = tokenInfo[@"appKey"];
        httping.uin = tokenInfo[@"uin"];
        httping.region = tokenInfo[@"region"];
        httping.topicId = tokenInfo[@"topic_id"];
    }else{
        httping.topicId = _topicId;
    }
    httping.endPoint = _config.endpoint;
    [httping start:complate];
}

- (void) tcpPingv2:(CLSTcpRequest *) request complate:(CompleteCallback)complate{
    if (![self validateParamsWithRequest:request.domain]) {
        NSLog(@"param error");
        return;
    }
    
    CLSMultiInterfaceTcping *tcpPing = [[CLSMultiInterfaceTcping alloc] initWithRequest:request];
    if(_netToken != nil && _netToken.length != 0){
        NSDictionary *tokenInfo = [CLSNetworkUtils parseNetToken:_netToken];
        if (tokenInfo.count == 0 && _topicId == nil) {
            NSLog(@"token parse failed，token:%@", _netToken);
            return;
        }
        tcpPing.networkAppId = tokenInfo[@"networkAppId"];
        tcpPing.appKey = tokenInfo[@"appKey"];
        tcpPing.uin = tokenInfo[@"uin"];
        tcpPing.region = tokenInfo[@"region"];
        tcpPing.topicId = tokenInfo[@"topic_id"];
    }else{
        tcpPing.topicId = _topicId;
    }
    tcpPing.endPoint = _config.endpoint;
    [tcpPing start:complate];
}
- (void) pingv2:(CLSPingRequest *) request complate:(CompleteCallback)complate{
    if (![self validateParamsWithRequest:request.domain]) {
        NSLog(@"param error");
        return;
    }
    
    CLSMultiInterfacePing *ping = [[CLSMultiInterfacePing alloc] initWithRequest:request];
    if(_netToken != nil && _netToken.length != 0){
        NSDictionary *tokenInfo = [CLSNetworkUtils parseNetToken:_netToken];
        if (tokenInfo.count == 0 && _topicId == nil) {
            NSLog(@"token parse failed，token:%@", _netToken);
            return;
        }
        ping.networkAppId = tokenInfo[@"networkAppId"];
        ping.appKey = tokenInfo[@"appKey"];
        ping.uin = tokenInfo[@"uin"];
        ping.region = tokenInfo[@"region"];
        ping.topicId = tokenInfo[@"topic_id"];
    }else{
        ping.topicId = _topicId;
    }
    ping.endPoint = _config.endpoint;
    [ping start:complate];
}

- (void) dns:(CLSDnsRequest *) request complate:(CompleteCallback)complate{
    if (![self validateParamsWithRequest:request.domain]) {
        NSLog(@"param error");
        return;
    }
    
    CLSMultiInterfaceDns *dns = [[CLSMultiInterfaceDns alloc] initWithRequest:request];
    if(_netToken != nil && _netToken.length != 0){
        NSDictionary *tokenInfo = [CLSNetworkUtils parseNetToken:_netToken];
        if (tokenInfo.count == 0 && _topicId == nil) {
            NSLog(@"token parse failed，token:%@", _netToken);
            return;
        }
        dns.networkAppId = tokenInfo[@"networkAppId"];
        dns.appKey = tokenInfo[@"appKey"];
        dns.uin = tokenInfo[@"uin"];
        dns.region = tokenInfo[@"region"];
        dns.topicId = tokenInfo[@"topic_id"];
    }else{
        dns.topicId = _topicId;
    }
    dns.endPoint = _config.endpoint;
    [dns start:complate];
}
- (void) mtr:(CLSMtrRequest *) request complate:(CompleteCallback)complate{
    if (![self validateParamsWithRequest:request.domain]) {
        NSLog(@"param error");
        return;
    }
    
    CLSMultiInterfaceMtr *mtr = [[CLSMultiInterfaceMtr alloc] initWithRequest:request];
    if(_netToken != nil && _netToken.length != 0){
        NSDictionary *tokenInfo = [CLSNetworkUtils parseNetToken:_netToken];
        if (tokenInfo.count == 0 && _topicId == nil) {
            NSLog(@"token parse failed，token:%@", _netToken);
            return;
        }
        mtr.networkAppId = tokenInfo[@"networkAppId"];
        mtr.appKey = tokenInfo[@"appKey"];
        mtr.uin = tokenInfo[@"uin"];
        mtr.region = tokenInfo[@"region"];
        mtr.topicId = tokenInfo[@"topic_id"];
    }else{
        mtr.topicId = _topicId;
    }
    mtr.endPoint = _config.endpoint;
    [mtr start:complate];
}
@end
