#import "CLSSignatureTool.h"


@implementation CLSSignatureTool

+ (NSString *)sha1:(NSData *)data {
    if (!data) return @"";
    
    unsigned char digest[CC_SHA1_DIGEST_LENGTH]; // 修正：使用CC_SHA1_DIGEST_LENGTH（CommonCrypto中定义）
    memset(digest, 0, CC_SHA1_DIGEST_LENGTH);
    
    CC_SHA1_CTX ctx; // 修正：使用CommonCrypto的CC_SHA1_CTX
    CC_SHA1_Init(&ctx);
    CC_SHA1_Update(&ctx, data.bytes, (CC_LONG)data.length);
    CC_SHA1_Final(digest, &ctx);
    
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (unsigned i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) { // 修正：使用CC_SHA1_DIGEST_LENGTH
        [result appendFormat:@"%02x", digest[i]];
    }
    return result;
}

+ (NSString *)hmacSha1WithKey:(NSString *)key data:(NSData *)data {
    if (!key || !data) return @"";
    
    unsigned char result[CC_SHA1_DIGEST_LENGTH];
    const char *keyBytes = [key cStringUsingEncoding:NSUTF8StringEncoding];
    CCHmac(kCCHmacAlgSHA1, keyBytes, strlen(keyBytes), data.bytes, data.length, result);
    
    NSMutableString *hmacStr = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [hmacStr appendFormat:@"%02x", result[i]];
    }
    return hmacStr;
}

// 其他方法（urlEncode、stringToLower）保持不变
+ (NSString *)urlEncode:(NSString *)str {
    if (!str) return @"";
    
    const char *s = [str cStringUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *encodedData = [NSMutableData data];
    unsigned char hexchars[] = "0123456789ABCDEF";
    
    const unsigned char *p = (const unsigned char *)s;
    for (; *p; p++) {
        if (isalnum(*p) || *p == '-' || *p == '_' || *p == '.' || *p == '~') {
            [encodedData appendBytes:p length:1];
        } else {
            [encodedData appendBytes:"%" length:1];
            [encodedData appendBytes:&hexchars[(*p) >> 4] length:1];
            [encodedData appendBytes:&hexchars[(*p) & 0x0F] length:1];
        }
    }
    return [[NSString alloc] initWithData:encodedData encoding:NSUTF8StringEncoding];
}

+ (NSString *)stringToLower:(NSString *)str {
    if (!str) return @"";
    
    NSMutableString *lowerStr = [NSMutableString stringWithCapacity:str.length];
    for (NSUInteger i = 0; i < str.length; i++) {
        unichar c = [str characterAtIndex:i];
        [lowerStr appendFormat:@"%c", tolower(c)];
    }
    return lowerStr;
}

@end
