//
//  CLSNetWorkScheme.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/8.
//

#import <Foundation/Foundation.h>
#import "CLSConfig.h"

NS_ASSUME_NONNULL_BEGIN

@interface CLSNetWorkScheme : NSObject
@property(nonatomic, strong) NSString * app_id;
@property(nonatomic, strong) NSString * app_name;
@property(nonatomic, strong) NSString * channel;
@property(nonatomic, strong) NSString * channel_name;
@property(nonatomic, strong) NSString * user_nick;
@property(nonatomic, strong) NSString * user_id;
@property(nonatomic, strong) NSString * long_login_nick;
@property(nonatomic, strong) NSString * long_login_user_id;
@property(nonatomic, strong) NSString * logon_type;
@property(nonatomic, strong) NSString * brand;
@property(nonatomic, strong) NSString * device_model;
@property(nonatomic, strong) NSString * os;
@property(nonatomic, strong) NSString * os_version;
@property(nonatomic, strong) NSString * carrier;
@property(nonatomic, strong) NSString * access;
@property(nonatomic, strong) NSString * access_subtype;
@property(nonatomic, strong) NSString * network_type;
@property(nonatomic, strong) NSString * reserves;
@property(nonatomic, strong) NSString * local_time;
@property(nonatomic, strong) NSString * local_timestamp;
@property(nonatomic, strong) NSString * result;
@property(nonatomic, strong) NSString * app_version;
@property(nonatomic, strong) NSString * utdid;
@property(nonatomic, strong) NSString * method;
@property(nonatomic, strong) NSMutableDictionary * ext;
@property(nonatomic, strong) NSString * dns;

+ (CLSNetWorkScheme *) createDefault;
+ (CLSNetWorkScheme *) createDefaultWithCLSConfig: (CLSConfig *) config;
+ (NSString *) fillWithDashIfEmpty: (NSString *) content;
- (NSDictionary *) toDictionary;
- (NSDictionary *) toDictionaryWithIgnoreExt: (BOOL) ignore;
@end

NS_ASSUME_NONNULL_END

