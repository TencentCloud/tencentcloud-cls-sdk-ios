#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h> // 关键：引入CommonCrypto库
#import <time.h>
#import <ctype.h>

@interface CLSSignatureTool : NSObject

/**
 对应C语言的_sha1函数
 计算SHA1哈希并转为小写十六进制字符串
 */
+ (NSString *)sha1:(NSData *)data;

/**
 对应C语言的_hmac_sha1函数
 计算HMAC-SHA1哈希并转为小写十六进制字符串
 */
+ (NSString *)hmacSha1WithKey:(NSString *)key data:(NSData *)data;

/**
 对应C语言的urlencode函数
 对字符串进行URL编码（大写字母，保留指定字符）
 */
+ (NSString *)urlEncode:(NSString *)str;

/**
 对应C语言的strlowr函数
 将字符串转为小写
 */
+ (NSString *)stringToLower:(NSString *)str;

@end

