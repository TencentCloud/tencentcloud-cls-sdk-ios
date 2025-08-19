//
//  ClsAdapter.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>
#import "baseClsPlugin.h"
#import "TencentCloudLogProducer.h"
#import "ClsConfig.h"
NS_ASSUME_NONNULL_BEGIN

@interface ClsAdapter : NSObject
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
- (void) setClsChannel: (NSString *)channel;
- (void) setClsChannelName: (NSString *)channelName;
- (void) setClsUserNick: (NSString *)userNick;
- (void) setClsLongLoginNick: (NSString *)longLoginNick;
- (void) setClsLoginType: (NSString *)loginType;

- (BOOL) initWithCLSConfig: (ClsConfig *) config;
- (BOOL) addClsPlugin: (baseClsPlugin *) plugin;
- (void) removeClsPlugin: (baseClsPlugin *) plugin;
- (void) reportClsCustomEvent: (NSString *) eventId properties:(nonnull NSDictionary *)dictionary;
@end

NS_ASSUME_NONNULL_END
