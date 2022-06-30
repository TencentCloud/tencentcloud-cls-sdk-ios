//
//  CLSNetWorkScheme.m
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/8.
//

#import "CLSNetWorkScheme.h"
#import "CLSSystemCapabilities.h"
#import "CLSUtils.h"

#if CLS_HAS_UIKIT
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

//#import "utdid/Utdid.h"
#import "TimeUtils.h"

@interface CLSNetWorkScheme ()
-(void) putIfNotNull:(NSMutableDictionary *)dictionay andKey:(NSString *)key andValue:(NSString *)value;
-(NSString *)returnDashIfNull: (NSString *)value;
-(void) put:(NSMutableDictionary *)dictionay andKey:(NSString *)key andValue:(NSString *)value;
@end


@implementation CLSNetWorkScheme

#pragma mark - construct
+ (CLSNetWorkScheme *)createDefault {
    CLSNetWorkScheme *scheme = [[CLSNetWorkScheme alloc] init];
    
    NSDate *date = [NSDate date];
    scheme.local_timestamp = [NSString stringWithFormat:@"%.0f", [date timeIntervalSince1970] * 1000];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc]init];
    [dateFormatter setDateFormat:@"YYYY-MM-dd HH:mm:ss:SSS"];
    [dateFormatter setTimeZone:[NSTimeZone systemTimeZone]];
    scheme.local_time = [dateFormatter stringFromDate:date];
    
    date = [NSDate dateWithTimeIntervalSince1970:[[NSString stringWithFormat:@"%ld%@%@", (long)[TimeUtils getTimeInMilliis], @".",[scheme.local_timestamp substringFromIndex:10]] doubleValue]];
    

    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    
    scheme.app_name = [scheme returnDashIfNull:[infoDictionary objectForKey:@"CFBundleDisplayName"]];
    if ([scheme.app_name isEqual:@"-"]) {
        scheme.app_name = [scheme returnDashIfNull: [infoDictionary objectForKey:@"CFBundleName"]];
    }
    
#if CLS_HOST_MAC
    scheme.brand = @"Apple";
#else
    scheme.brand = [scheme returnDashIfNull: [[UIDevice currentDevice] model]];
#endif

    scheme.device_model = [scheme returnDashIfNull:[CLSUtils getDeviceModel]];
#if CLS_HOST_MAC
    scheme.os = @"macOS";
#elif CLS_HOST_TV
    scheme.os = @"tvOS";
#else
    scheme.os = @"iOS";
#endif

#if CLS_HOST_MAC
    scheme.os_version = [scheme returnDashIfNull:[[NSProcessInfo processInfo] operatingSystemVersionString]];
#else
    scheme.os_version = [scheme returnDashIfNull:[[UIDevice currentDevice] systemVersion]];
#endif
    
    scheme.carrier = [scheme returnDashIfNull:[CLSUtils getCarrier]];
    scheme.access = [scheme returnDashIfNull:[CLSUtils getNetworkTypeName]];
    scheme.access_subtype = [scheme returnDashIfNull:[CLSUtils getNetworkSubTypeName]];

    return scheme;
}

+ (CLSNetWorkScheme *) createDefaultWithCLSConfig:(CLSConfig *)config {
    CLSNetWorkScheme *data = [self createDefault];
    
    [data setApp_id:[NSString stringWithFormat:@"%@@%@", config.pluginAppId, data.os]];
    [data setChannel:[data returnDashIfNull:config.channel]];
    [data setChannel_name:[data returnDashIfNull:config.channelName]];
    [data setUser_nick:[data returnDashIfNull:config.userNick]];
    [data setLong_login_nick:[data returnDashIfNull:config.longLoginNick]];
    [data setUser_id:[data returnDashIfNull:config.userId]];
    [data setLong_login_user_id:[data returnDashIfNull:config.longLoginUserId]];
    [data setLogon_type:[data returnDashIfNull:config.loginType]];
    [data setExt:[config.ext mutableCopy]];
    
    return data;
}

+ (NSString *)fillWithDashIfEmpty:(NSString *)content {
    return nil == content || [@"" isEqual:content] ? @"-" : content;
}

- (NSDictionary *)toDictionary {
    return [self toDictionaryWithIgnoreExt: NO];
}

- (NSDictionary *) toDictionaryWithIgnoreExt: (BOOL) ignore {
    NSMutableDictionary *fields =  [[NSMutableDictionary alloc] init];
    [self putIfNotNull:fields andKey:@"app_id" andValue: [self app_id]];
    [self putIfNotNull:fields andKey:@"app_name" andValue: [self app_name]];
    [self putIfNotNull:fields andKey:@"channel" andValue: [self channel]];
    [self putIfNotNull:fields andKey:@"channel_name" andValue: [self channel_name]];
    [self putIfNotNull:fields andKey:@"user_nick" andValue: [self user_nick]];
    [self putIfNotNull:fields andKey:@"long_login_nick" andValue: [self long_login_nick]];
    [self putIfNotNull:fields andKey:@"logon_type" andValue: [self logon_type]];
    [self putIfNotNull:fields andKey:@"user_id" andValue: [self user_id]];
    [self putIfNotNull:fields andKey:@"long_login_user_id" andValue: [self long_login_user_id]];
    [self putIfNotNull:fields andKey:@"device_model" andValue: [self device_model]];
    [self putIfNotNull:fields andKey:@"os" andValue: [self os]];
    [self putIfNotNull:fields andKey:@"os_version" andValue: [self os_version]];
    [self putIfNotNull:fields andKey:@"carrier" andValue: [self carrier]];
    [self putIfNotNull:fields andKey:@"access" andValue: [self access]];
    [self putIfNotNull:fields andKey:@"access_subtype" andValue: [self access_subtype]];
    [self putIfNotNull:fields andKey:@"network_type" andValue: [self network_type]];
    [self putIfNotNull:fields andKey:@"reserves" andValue: [self reserves]];
    [self putIfNotNull:fields andKey:@"local_time" andValue: [self local_time]];
    [self putIfNotNull:fields andKey:@"local_timestamp" andValue: [self local_timestamp]];
    [self putIfNotNull:fields andKey:@"result" andValue: [self result]];
    [self putIfNotNull:fields andKey:@"domain" andValue: [self domain]];
    
    // ignore ext fields
    if (ignore) {
        return fields;
    }

    for (NSString *key in _ext) {
        NSString *value =_ext[key];
        [self put:fields andKey:key andValue:value];
    }
    
    return fields;
}

- (void) putIfNotNull:(NSMutableDictionary *)dictionay andKey:(NSString *)key andValue:(NSString *)value {
    if (key && value) {
        [dictionay setValue:value forKey:key];
    }
}

- (NSString *)returnDashIfNull:(NSString *)value {
    if (!value) {
        return @"-";
    }
    
    return value;
}

- (void)put:(NSMutableDictionary *)dictionay andKey:(NSString *)key andValue:(NSString *)value
{
    if (nil == key) {
        key = @"null";
    }
    
    if (nil == value) {
        value = @"null";
    }
    
    [dictionay setValue:value forKey:key];
}

@end

