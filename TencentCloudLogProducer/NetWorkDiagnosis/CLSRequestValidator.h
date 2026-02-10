//
//  CLSRequestValidator.h
//  TencentCloudLogProducer
//
//  Created by AI Assistant on 2026/01/21.
//  参数校验工具类：为所有网络探测请求提供统一的参数合法性校验
//

#import <Foundation/Foundation.h>
#import "ClsProtocols.h"

NS_ASSUME_NONNULL_BEGIN

/// 网络探测参数校验工具类
@interface CLSRequestValidator : NSObject

/// 校验通用参数（maxTimes, timeout, size, domain）
/// @param request 请求对象
/// @param error 错误信息（如果校验失败）
/// @return 校验是否通过
+ (BOOL)validateCommonParameters:(CLSRequest *)request error:(NSError **)error;

/// 校验 TCP 请求特定参数
/// @param request TCP 请求对象
/// @param error 错误信息（如果校验失败）
/// @return 校验是否通过
+ (BOOL)validateTcpRequest:(CLSTcpRequest *)request error:(NSError **)error;

/// 校验 HTTP 请求特定参数
/// @param request HTTP 请求对象
/// @param error 错误信息（如果校验失败）
/// @return 校验是否通过
+ (BOOL)validateHttpRequest:(CLSHttpRequest *)request error:(NSError **)error;

/// 校验 Ping 请求特定参数
/// @param request Ping 请求对象
/// @param error 错误信息（如果校验失败）
/// @return 校验是否通过
+ (BOOL)validatePingRequest:(CLSPingRequest *)request error:(NSError **)error;

/// 校验 DNS 请求特定参数
/// @param request DNS 请求对象
/// @param error 错误信息（如果校验失败）
/// @return 校验是否通过
+ (BOOL)validateDnsRequest:(CLSDnsRequest *)request error:(NSError **)error;

/// 校验 MTR 请求特定参数
/// @param request MTR 请求对象
/// @param error 错误信息（如果校验失败）
/// @return 校验是否通过
+ (BOOL)validateMtrRequest:(CLSMtrRequest *)request error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
