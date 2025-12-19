//
//  CLSStringUtils.m
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import "CLSStringUtils.h"

@implementation CLSStringUtils
#pragma mark - 安全数据类型处理

// 清理字符串，确保是NSString类型
+ (NSString *)sanitizeString:(id)value {
    if (value == nil || value == [NSNull null]) {
        return nil;
    }
    
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    
    // 将其他类型转换为字符串
    return [NSString stringWithFormat:@"%@", value];
}

// 清理数字，确保是NSNumber类型
+ (NSNumber *)sanitizeNumber:(id)value {
    if (value == nil || value == [NSNull null]) {
        return nil;
    }
    
    if ([value isKindOfClass:[NSNumber class]]) {
        return value;
    }
    
    if ([value isKindOfClass:[NSString class]]) {
        // 尝试将字符串转换为数字
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        return [formatter numberFromString:value];
    }
    
    return nil;
}

// 清理headers字典
+ (NSDictionary *)sanitizeHeaders:(NSDictionary *)headers {
    if (!headers) {
        // 返回默认headers
        return @{
            @"cache-control": @"s-maxage=10, stale-while-revalidate",
            @"content-encoding": @"gzip",
            @"content-type": @"text/html; charset=utf-8",
            @"date": @"Sun, 28 Sep 2025 08:48:22 GMT",
            @"eo-cache-status": @"MISS",
            @"eo-log-uuid": @"15161754276796208429",
            @"etag": @"\"851c8-6qKq//Y3Rw34FPXBN1lz+CIWHx8\"",
            @"ratelimit-limit": @"200",
            @"ratelimit-policy": @"200;w=5",
            @"ratelimit-remaining": @"199",
            @"ratelimit-reset": @"5",
            @"server": @"nginx",
            @"set-cookie": @"intl_language=en; Max-Age=15552000; Domain=.tencentcloud.com; Path=/; Expires=Fri, 27 Mar 2026 08:48:22 GMT",
            @"vary": @"Accept-Encoding",
            @"x-powered-by": @"Next.js",
            @"x-req-id": @"S5_Gqmn3",
            @"x-trace-id": @"f89e13c1c74d3e378999436c4997fe0e"
        };
    }
    
    NSMutableDictionary *sanitizedHeaders = [NSMutableDictionary dictionary];
    [headers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString *sanitizedKey = [self sanitizeString:key];
        NSString *sanitizedValue = [self sanitizeString:obj];
        
        if (sanitizedKey && sanitizedValue) {
            sanitizedHeaders[[sanitizedKey lowercaseString]] = sanitizedValue;
        }
    }];
    
    return [sanitizedHeaders copy];
}

// 清理desc字典
+ (NSDictionary *)sanitizeDesc:(NSDictionary *)desc {
    if (!desc) {
        // 返回默认desc
        return @{};
    }
    
    return [self sanitizeDictionary:desc];
}

// 通用字典清理方法
+ (NSDictionary *)sanitizeDictionary:(NSDictionary *)dict {
    if (!dict) {
        return @{}; // 返回空字典而不是nil
    }
    
    NSMutableDictionary *sanitizedDict = [NSMutableDictionary dictionary];
    [dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        id sanitizedKey = [self sanitizeString:key];
        id sanitizedValue = [self sanitizeValue:obj];
        
        if (sanitizedKey && sanitizedValue) {
            sanitizedDict[sanitizedKey] = sanitizedValue;
        }
    }];
    
    return [sanitizedDict copy];
}

// 通用值清理方法
+ (id)sanitizeValue:(id)value {
    if (value == nil || value == [NSNull null]) {
        return [NSNull null]; // JSON兼容的空值
    }
    
    // 处理基础类型
    if ([value isKindOfClass:[NSString class]] ||
        [value isKindOfClass:[NSNumber class]] ||
        [value isKindOfClass:[NSNull class]]) {
        return value;
    }
    
    // 处理字典
    if ([value isKindOfClass:[NSDictionary class]]) {
        return [self sanitizeDictionary:value];
    }
    
    // 处理数组
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *sanitizedArray = [NSMutableArray array];
        for (id item in value) {
            id sanitizedItem = [self sanitizeValue:item];
            if (sanitizedItem) {
                [sanitizedArray addObject:sanitizedItem];
            }
        }
        return sanitizedArray;
    }
    
    // 其他类型转换为字符串
    return [NSString stringWithFormat:@"%@", value];
}

+ (NSString *)convertToJSONString:(NSDictionary *)dictionary {
    // 1. 验证字典是否为空
    if (!dictionary || ![dictionary isKindOfClass:[NSDictionary class]]) {
        return @"{}"; // 返回空JSON对象
    }
    
    // 2. 验证字典是否能被序列化为JSON
    if (![NSJSONSerialization isValidJSONObject:dictionary]) {
        NSLog(@"⚠️ 字典包含非JSON兼容的数据类型");
        return @"{}";
    }
    
    // 3. 尝试序列化
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionary
                                                      options:NSJSONWritingPrettyPrinted
                                                        error:&error];
    
    // 4. 处理错误情况
    if (error || !jsonData) {
        NSLog(@"JSON序列化失败: %@", error.localizedDescription);
        return @"{}";
    }
    
    // 5. 转换为字符串
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

+ (NSString *)formatDateToMillisecondString:(NSDate *)date {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    [formatter setTimeZone:[NSTimeZone systemTimeZone]]; // 使用系统当前时区
    NSString *dateString = [formatter stringFromDate:date];
    return dateString;
}

+ (NSString *)getSdkVersion {
    // 从 bundle 中读取版本号，与 podspec 保持同步
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    
    // 如果无法从 bundle 读取（例如未打包场景），使用默认版本号
    return version ?: @"3.0.0";
}
@end
