//
//  CLSAdapter.m
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import "CLSAdapter.h"


@implementation CLSAdapter
- (void) setChannel: (NSString *)channel{
    _channel = channel;
}
- (void) setChannelName: (NSString *)channelName{
    _channelName = channelName;
}
- (void) setUserNick: (NSString *)userNick{
    _userNick = userNick;
}
- (void) setLongLoginNick: (NSString *)longLoginNick{
    _longLoginNick = longLoginNick;
}
- (void) setLoginType: (NSString *)loginType {
    _loginType = loginType;
}

+ (instancetype)sharedInstance {
    static CLSAdapter * ins = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ins = [[CLSAdapter alloc] init];
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

- (BOOL) initWithCLSConfig:(CLSConfig *)config {
    CLSLogV(@"start.");
    NSLog(config.description);
    for (int i = 0; i < _plugins.count; i++) {
        basePlugin *plugin = _plugins[i];
        CLSLogV(@"start init plugin: %@", [plugin name]);
        [plugin initWithCLSConfig:config];
        CLSLogV(@"end init plugin: %@", [plugin name]);
    }

    CLSLogV(@"end.");
    return YES;
}

#pragma mark - plugin manager
- (BOOL) addPlugin: (basePlugin *) plugin {
    if (nil == plugin) {
        return NO;
    }
    
    if ([_plugins containsObject:plugin]) {
        return NO;
    }
    
    [_plugins addObject:plugin];
    return YES;
}
- (void) removePlugin: (basePlugin *) plugin{
    if ([_plugins containsObject:plugin]) {
        [_plugins removeObject:plugin];
    }
}
@end
