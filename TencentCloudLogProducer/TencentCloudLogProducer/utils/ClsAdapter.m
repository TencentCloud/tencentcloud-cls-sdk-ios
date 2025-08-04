//
//  ClsAdapter.m
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import "ClsAdapter.h"


@implementation ClsAdapter
- (void) setClsChannel: (NSString *)channel{
    _channel = channel;
}
- (void) setClsChannelName: (NSString *)channelName{
    _channelName = channelName;
}
- (void) setClsUserNick: (NSString *)userNick{
    _userNick = userNick;
}
- (void) setClsLongLoginNick: (NSString *)longLoginNick{
    _longLoginNick = longLoginNick;
}
- (void) setClsLoginType: (NSString *)loginType {
    _loginType = loginType;
}

+ (instancetype)sharedInstance {
    static ClsAdapter * ins = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ins = [[ClsAdapter alloc] init];
    });
    return ins;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _plugins = [[NSMutableArray alloc] init];
    }
    return self;
}

- (BOOL) initWithCLSConfig:(ClsConfig *)config {
    CLSLogV(@"start.");
    NSLog(config.description);
    for (int i = 0; i < _plugins.count; i++) {
        baseClsPlugin *plugin = _plugins[i];
        CLSLogV(@"start init plugin: %@", [plugin name]);
        [plugin initWithCLSConfig:config];
        CLSLogV(@"end init plugin: %@", [plugin name]);
    }

    CLSLogV(@"end.");
    return YES;
}

#pragma mark - plugin manager
- (BOOL) addClsPlugin: (baseClsPlugin *) plugin {
    if (nil == plugin) {
        return NO;
    }
    
    if ([_plugins containsObject:plugin]) {
        return NO;
    }
    
    [_plugins addObject:plugin];
    return YES;
}
- (void) removeClsPlugin: (baseClsPlugin *) plugin{
    if ([_plugins containsObject:plugin]) {
        [_plugins removeObject:plugin];
    }
}
@end
