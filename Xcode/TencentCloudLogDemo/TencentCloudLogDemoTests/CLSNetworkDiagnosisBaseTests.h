//
//  CLSNetworkDiagnosisBaseTests.h
//  TencentCloudLogDemoTests
//
//  Created by AI Assistant on 2026/01/04.
//

@import XCTest;
@import TencentCloudLogProducer;

NS_ASSUME_NONNULL_BEGIN

/// 测试通用超时时间
static NSTimeInterval const kTestDefaultTimeout = 30.0;
/// 纳秒时间戳最小值
static long long const kMinNanoTimestamp = 1000000000000LL;
/// 测试通用AppKey
static NSString *const kTestAppKey = @"zhiyan_test_key";
/// 测试目标域名
static NSString *const kTestDomain = @"www.baidu.com";

/**
 * 网络探测测试基类
 * 
 * 支持的探测参数：
 * - DNS:     domain、detectEx、enableMultiplePortsDetect、prefer、nameserver、timeout
 * - Ping:    domain、detectEx、enableMultiplePortsDetect、maxTimes、size、timeout
 * - HTTP:    domain、detectEx、enableSSLVerification、enableMultiplePortsDetect、timeout
 * - TCPPing: domain、port、detectEx、enableMultiplePortsDetect、maxTimes、timeout
 * - MTR:     domain、detectEx、enableMultiplePortsDetect、maxTimes、timeout、maxTTL、protocol
 * 
 * 注意：userEx 已移除，统一从 ClsNetworkDiagnosis 获取
 */
@interface CLSNetworkDiagnosisBaseTests : XCTestCase

@property (nonatomic, strong) ClsNetworkDiagnosis *diagnosis;

#pragma mark - 工具方法
- (NSDictionary *)parseResponseContent:(CLSResponse *)response;
- (NSDictionary *)safeConvertToDictionary:(id)rawValue;
- (NSArray *)safeConvertToArray:(id)rawValue;
- (NSDictionary *)dictionaryFromString:(NSString *)string error:(NSError * _Nullable * _Nullable)error;

#pragma mark - 公共字段校验
/// 校验公共字段: name、traceID、start、duration、end、service
- (void)validateCommonFields:(NSDictionary *)data;

/// 校验Resource字段（资源/环境字段层）
- (void)validateResourceFields:(NSDictionary *)data;

/// 校验Attribute字段（探测信息节点）
- (void)validateAttributeFields:(NSDictionary *)data expectedType:(NSString *)type;

/// 校验net.origin基础字段: method、trace_id、appKey、src
- (void)validateNetOriginFields:(NSDictionary *)data expectedMethod:(NSString *)method;

/// 校验netInfo字段（探测网络环境信息）
- (void)validateNetInfo:(NSDictionary *)netInfo;

/// 校验扩展字段: detectEx（业务扩展）、userEx（全局用户扩展）
- (void)validateExtensionFields:(NSDictionary *)data 
               expectedDetectEx:(NSDictionary * _Nullable)expectedDetectEx;

/// 校验 userEx 全局字段（验证通过 setUserEx 设置的值已正确上报）
- (void)validateUserExFields:(NSDictionary *)data 
              expectedUserEx:(NSDictionary * _Nullable)expectedUserEx;

/// 通用字段非空校验
- (void)validateNonNilValueInDict:(NSDictionary *)dict key:(NSString *)key failureMessage:(NSString *)message;

#pragma mark - Ping 专项校验
/// 校验Ping专用字段: host、host_ip、interface、count、size、total、loss、latency_*、stddev等
- (void)validatePingOriginFields:(NSDictionary *)origin;

/// 校验Ping统计字段逻辑
- (void)validatePingStatisticsFields:(NSDictionary *)origin expectedCount:(NSInteger)count expectedSize:(NSInteger)size;

#pragma mark - TCPPing 专项校验
/// 校验TCPPing专用字段: host、host_ip、port、interface、count、total、loss、latency_*等
- (void)validateTcppingOriginFields:(NSDictionary *)origin expectedPort:(NSInteger)port;

/// 校验TCPPing统计字段逻辑
- (void)validateTcppingStatisticsFields:(NSDictionary *)origin expectedCount:(NSInteger)count;

#pragma mark - DNS 专项校验
/// 校验DNS专用字段: domain、status、id、flags、latency、host_ip、QUESTION_SECTION等
- (void)validateDnsOriginFields:(NSDictionary *)origin;

/// 校验DNS解析结果（ANSWER_SECTION）
- (void)validateDnsAnswerFields:(NSDictionary *)origin;

#pragma mark - HTTP 专项校验
/// 校验HTTP专用字段: url、host_ip、domain、remoteAddr、各时间字段、httpCode等
- (void)validateHttpOriginFields:(NSDictionary *)origin;

/// 校验HTTP时间字段逻辑
- (void)validateHttpTimeFields:(NSDictionary *)origin;

/// 校验HTTP headers字段
- (void)validateHttpHeadersFields:(NSDictionary *)data;

/// 校验HTTP desc字段（请求生命周期时间点）
- (void)validateHttpDescFields:(NSDictionary *)data;

/// 校验HTTP desc时间序列
- (void)validateHttpDescTimeSequence:(NSDictionary *)desc;

#pragma mark - MTR 专项校验
/// 校验MTR专用字段: host、type、max_paths、paths
- (void)validateMtrOriginFields:(NSDictionary *)origin;

/// 校验MTR paths数组
- (void)validateMtrPathsFields:(NSArray *)paths expectedProtocol:(NSString * _Nullable)protocol;

/// 校验MTR单跳字段: hop、ip、loss、latency_*、responseNum、stddev
- (void)validateMtrHopFields:(NSDictionary *)hop;

#pragma mark - IP地址校验
- (BOOL)isIPv4Address:(NSString *)address;
- (BOOL)isIPv6Address:(NSString *)address;

#pragma mark - 日志方法
- (void)logKeyResult:(NSDictionary *)data withTitle:(NSString *)title;
- (void)logCompleteResult:(NSDictionary *)data withTitle:(NSString *)title;

@end

NS_ASSUME_NONNULL_END
