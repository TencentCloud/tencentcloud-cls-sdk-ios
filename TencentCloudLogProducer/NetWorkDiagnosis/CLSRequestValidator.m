//
//  CLSRequestValidator.m
//  TencentCloudLogProducer
//
//  Created by AI Assistant on 2026/01/21.
//

#import "CLSRequestValidator.h"

// 错误域
static NSString * const kCLSValidationErrorDomain = @"CLSValidationError";

// 错误码定义
typedef NS_ENUM(NSInteger, CLSValidationErrorCode) {
    CLSValidationErrorMaxTimes = -1001,      // maxTimes 参数非法
    CLSValidationErrorTimeout = -1002,       // timeout 参数非法
    CLSValidationErrorSize = -1003,          // size 参数非法
    CLSValidationErrorDomain = -1004,        // domain 参数非法
    CLSValidationErrorPort = -1005,          // port 参数非法
    CLSValidationErrorInterval = -1006,      // interval 参数非法
    CLSValidationErrorPrefer = -1007,        // prefer 参数非法
    CLSValidationErrorMaxTTL = -1008,        // maxTTL 参数非法
    CLSValidationErrorProtocol = -1009,      // protocol 参数非法
};

@implementation CLSRequestValidator

#pragma mark - 通用参数校验

+ (BOOL)validateCommonParameters:(CLSRequest *)request error:(NSError **)error {
    // 1. 校验 maxTimes (探测次数: 1-100)
    if (request.maxTimes < 1 || request.maxTimes > 100) {
        if (error) {
            *error = [self errorWithCode:CLSValidationErrorMaxTimes
                                 message:[NSString stringWithFormat:@"maxTimes 参数非法: %d (有效范围: 1-100)", request.maxTimes]];
        }
        return NO;
    }
    
    // 2. 校验 timeout (超时时间: 0 < timeout ≤ 300000 ms，单位：毫秒)
    if (request.timeout <= 0 || request.timeout > 300000) {
        if (error) {
            *error = [self errorWithCode:CLSValidationErrorTimeout
                                 message:[NSString stringWithFormat:@"timeout 参数非法: %d (有效范围: 0 < timeout ≤ 300000ms)", request.timeout]];
        }
        return NO;
    }
    
    // 3. 校验 size (包大小: 8-1024字节)
    if (request.size < 8 || request.size > 1024) {
        if (error) {
            *error = [self errorWithCode:CLSValidationErrorSize
                                 message:[NSString stringWithFormat:@"size 参数非法: %d (有效范围: 8-1024字节)", request.size]];
        }
        return NO;
    }
    
    // 4. 校验 domain (必填)
    if (!request.domain || request.domain.length == 0) {
        if (error) {
            *error = [self errorWithCode:CLSValidationErrorDomain
                                 message:@"domain 参数不能为空"];
        }
        return NO;
    }
    
    return YES;
}

#pragma mark - TCP 请求校验

+ (BOOL)validateTcpRequest:(CLSTcpRequest *)request error:(NSError **)error {
    // 先校验通用参数
    if (![self validateCommonParameters:request error:error]) {
        return NO;
    }
    
    // 校验 port (端口号: 1-65535)
    if (request.port < 1 || request.port > 65535) {
        if (error) {
            *error = [self errorWithCode:CLSValidationErrorPort
                                 message:[NSString stringWithFormat:@"port 参数非法: %ld (有效范围: 1-65535)", (long)request.port]];
        }
        return NO;
    }
    
    return YES;
}

#pragma mark - HTTP 请求校验

+ (BOOL)validateHttpRequest:(CLSHttpRequest *)request error:(NSError **)error {
    // HTTP 请求仅需校验通用参数
    return [self validateCommonParameters:request error:error];
}

#pragma mark - Ping 请求校验

+ (BOOL)validatePingRequest:(CLSPingRequest *)request error:(NSError **)error {
    // 先校验通用参数
    if (![self validateCommonParameters:request error:error]) {
        return NO;
    }
    
    // 校验 interval (间隔时间: 100-10000ms)
    if (request.interval < 100 || request.interval > 10000) {
        if (error) {
            *error = [self errorWithCode:CLSValidationErrorInterval
                                 message:[NSString stringWithFormat:@"interval 参数非法: %d (有效范围: 100-10000ms)", request.interval]];
        }
        return NO;
    }
    
    // 校验 prefer (IP协议偏好: -1 或 0-3)
    if (request.prefer < -1 || request.prefer > 3) {
        if (error) {
            *error = [self errorWithCode:CLSValidationErrorPrefer
                                 message:[NSString stringWithFormat:@"prefer 参数非法: %d (有效值: -1=自动, 0=IPv4优先, 1=IPv6优先, 2=仅IPv4, 3=仅IPv6)", request.prefer]];
        }
        return NO;
    }
    
    return YES;
}

#pragma mark - DNS 请求校验

+ (BOOL)validateDnsRequest:(CLSDnsRequest *)request error:(NSError **)error {
    // 先校验通用参数
    if (![self validateCommonParameters:request error:error]) {
        return NO;
    }
    
    // 校验 prefer (IP协议偏好: -1 或 0-3)
    if (request.prefer < -1 || request.prefer > 3) {
        if (error) {
            *error = [self errorWithCode:CLSValidationErrorPrefer
                                 message:[NSString stringWithFormat:@"prefer 参数非法: %d (有效值: -1=自动, 0=IPv4优先, 1=IPv6优先, 2=仅IPv4, 3=仅IPv6)", request.prefer]];
        }
        return NO;
    }
    
    return YES;
}

#pragma mark - MTR 请求校验

+ (BOOL)validateMtrRequest:(CLSMtrRequest *)request error:(NSError **)error {
    // 先校验通用参数
    if (![self validateCommonParameters:request error:error]) {
        return NO;
    }
    
    // 校验 maxTTL (最大跳数: 1-64)
    if (request.maxTTL < 1 || request.maxTTL > 64) {
        if (error) {
            *error = [self errorWithCode:CLSValidationErrorMaxTTL
                                 message:[NSString stringWithFormat:@"maxTTL 参数非法: %d (有效范围: 1-64)", request.maxTTL]];
        }
        return NO;
    }
    
   // 校验 protocol (协议类型: icmp、udp 或 tcp)
    if (request.protocol && request.protocol.length > 0) {
        NSString *lowerProtocol = [request.protocol lowercaseString];
        if (![lowerProtocol isEqualToString:@"icmp"] && ![lowerProtocol isEqualToString:@"udp"] && ![lowerProtocol isEqualToString:@"tcp"]) {
            if (error) {
                *error = [self errorWithCode:CLSValidationErrorProtocol
                                     message:[NSString stringWithFormat:@"protocol 参数非法: %@ (有效值: icmp, udp, tcp)", request.protocol]];
            }
            return NO;
        }
    }
    
    // 校验 prefer (IP协议偏好: -1 或 0-3)
    if (request.prefer < -1 || request.prefer > 3) {
        if (error) {
            *error = [self errorWithCode:CLSValidationErrorPrefer
                                 message:[NSString stringWithFormat:@"prefer 参数非法: %d (有效值: -1=自动, 0=IPv4优先, 1=IPv6优先, 2=仅IPv4, 3=仅IPv6)", request.prefer]];
        }
        return NO;
    }
    
    return YES;
}

#pragma mark - 辅助方法

+ (NSError *)errorWithCode:(CLSValidationErrorCode)code message:(NSString *)message {
    return [NSError errorWithDomain:kCLSValidationErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@end
