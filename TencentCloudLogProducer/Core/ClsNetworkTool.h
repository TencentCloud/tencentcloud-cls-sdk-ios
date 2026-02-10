//
//  CLSNetworkTool.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/11/7.
//

#import <Foundation/Foundation.h>
#import "ClsLogs.pbobjc.h"
#import "ClsLogModel.h"

// 发送选项（对应 C 层 cls_log_post_option）
@interface ClsPostOption : NSObject
@property (nonatomic, assign) NSInteger compressType; // 1=LZ4压缩
@property (nonatomic, assign) NSTimeInterval socketTimeout; // 超时时间（秒）
@property (nonatomic, assign) NSTimeInterval connectTimeout; // 连接超时（秒）
@end

// 发送结果（对应 C 层 post_cls_result）
@interface CLSSendResult : NSObject
@property (nonatomic, assign) NSInteger statusCode; // HTTP状态码
@property (nonatomic, copy) NSString *requestID; // 服务端返回的RequestID
@property (nonatomic, copy) NSString *message; // 错误信息
@end

// 网络工具类（处理签名、压缩、HTTP请求）
@interface CLSNetworkTool : NSObject

// LZ4压缩（模拟C层压缩逻辑）
+ (NSData *)lz4CompressData:(NSData *)data;

+ (CLSSendResult *)sendPostRequestSyncWithUrl:(NSString *)url
                                      headers:(NSDictionary *)headers
                                        body:(NSData *)body
                                      option:(ClsPostOption *)option;

/**
 生成签名（严格对应C语言的signature函数）
 
 @param secretId 密钥ID（对应secret_id）
 @param secretKey 密钥Key（对应secret_key）
 @param method HTTP方法（对应method）
 @param path 请求路径（对应path）
 @param params 请求参数（NSDictionary，对应root_t params）
 @param headers 请求头（NSDictionary，对应root_t headers）
 @param expire 签名有效期（秒，对应expire）
 @return 签名字符串（对应c_signature）
 */
+ (NSString *)generateSignatureWithSecretId:(NSString *)secretId
                                secretKey:(NSString *)secretKey
                                   method:(NSString *)method
                                     path:(NSString *)path
                                    params:(NSDictionary<NSString *, NSString *> *)params
                                   headers:(NSDictionary<NSString *, NSString *> *)headers
                                    expire:(long)expire;


+ (uint64_t)sizeOfLogItem:(Log *)log;

// 计算聚合包大小（单位：字节）
+ (uint64_t)sizeOfLogGroupList:(LogGroupList *)logGroupList;

+ (BOOL)isNetworkAvailable;

@end
