//
//  CLSAdapter.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>
#import "basePlugin.h"
#import "TencentCloudLogProducer.h"
#import "CLSConfig.h"
NS_ASSUME_NONNULL_BEGIN

@interface CLSAdapter : NSObject
{
    @private
    NSString * _channel;
    NSString * _channelName;
    NSString * _userNick;
    NSString * _longLoginNick;
    NSString * _loginType;
    NSMutableArray * _plugins;
}
+ (instancetype) sharedInstance;
- (void) setChannel: (NSString *)channel;
- (void) setChannelName: (NSString *)channelName;
- (void) setUserNick: (NSString *)userNick;
- (void) setLongLoginNick: (NSString *)longLoginNick;
- (void) setLoginType: (NSString *)loginType;

- (BOOL) initWithCLSConfig: (CLSConfig *) config;
- (BOOL) addPlugin: (basePlugin *) plugin;
- (void) removePlugin: (basePlugin *) plugin;
- (void) reportCustomEvent: (NSString *) eventId properties:(nonnull NSDictionary *)dictionary;
@end

NS_ASSUME_NONNULL_END
