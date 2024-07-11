//
//  CLSNetworkDiagnosis.m
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import "CLSNetworkDiagnosis.h"

@interface CLSNetworkDiagnosis ()
@property(nonatomic, assign) long index;
@property(nonatomic, strong) NSLock *lock;

@property(nonatomic, strong) CLSConfig *config;
@property(nonatomic, strong) baseSender *sender;
@property(nonatomic, strong) NSMutableArray *callbacks;

- (NSString *) generateId;
@end

@implementation CLSNetworkDiagnosis
+ (instancetype)sharedInstance {
    static CLSNetworkDiagnosis * ins = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ins = [[CLSNetworkDiagnosis alloc] init];
    });
    return ins;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = [[NSLock alloc] init];
        _callbacks = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void) initWithConfig: (CLSConfig *)config sender: (baseSender *)sender {
    _config = config;
    _sender = sender;
}


- (void)ping:(NSString*)host size:(NSUInteger)size output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete{
    [CLSPing start:host size:size output:output complete:complete sender:_sender pingExt:nil];
}
- (void)ping:(NSString*)host size:(NSUInteger)size task_timeout:(NSUInteger)task_timeout output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete count:(NSInteger)count{
    [CLSPing start:host size:size task_timeout:task_timeout output:output complete:complete sender:_sender count:count pingExt:nil];
}

- (void)ping:(NSString*)host size:(NSUInteger)size output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete customFiled:(NSMutableDictionary*) customFiled{
    [CLSPing start:host size:size output:output complete:complete sender:_sender pingExt:customFiled];
}
- (void)ping:(NSString*)host size:(NSUInteger)size task_timeout:(NSUInteger)task_timeout output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete count:(NSInteger)count customFiled:(NSMutableDictionary*) customFiled{
    [CLSPing start:host size:size task_timeout:task_timeout output:output complete:complete sender:_sender count:count pingExt:customFiled];
}

//tcpPing
- (void)tcpPing:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete{
    [CLSTcpPing start:host output:output complete:complete sender:_sender tcpPingExt:nil];
}
- (void)tcpPing:(NSString*)host port:(NSUInteger)port task_timeout:(NSUInteger)task_timeout count:(NSInteger)count output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete{
    [CLSTcpPing start:host port:port task_timeout:task_timeout count:count output:output complete:complete sender:_sender tcpPingExt:nil];
}

- (void)tcpPing:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete customFiled:(NSMutableDictionary*) customFiled{
    [CLSTcpPing start:host output:output complete:complete sender:_sender tcpPingExt:customFiled];
}
- (void)tcpPing:(NSString*)host port:(NSUInteger)port task_timeout:(NSUInteger)task_timeout count:(NSInteger)count output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete customFiled:(NSMutableDictionary*) customFiled{
    [CLSTcpPing start:host port:port task_timeout:task_timeout count:count output:output complete:complete sender:_sender tcpPingExt:customFiled];
}
//
//traceroute
- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete{
    [CLSTraceRoute start:host output:output complete:complete sender:_sender traceRouteExt:nil];
}

- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete maxTtl:(NSInteger)maxTtl{
    [CLSTraceRoute start:host output:output complete:complete sender:_sender maxTtl:maxTtl traceRouteExt:nil];
}

- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete customFiled:(NSMutableDictionary*) customFiled{
    [CLSTraceRoute start:host output:output complete:complete sender:_sender traceRouteExt:customFiled];
}
- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete maxTtl:(NSInteger)maxTtl customFiled:(NSMutableDictionary*) customFiled{
    [CLSTraceRoute start:host output:output complete:complete sender:_sender maxTtl:maxTtl traceRouteExt:customFiled];
}

// httping
- (void) httping:(NSString*)url output:(id<CLSOutputDelegate>)output complate:(CLSHttpCompleteHandler)complate{
    [CLSHttp start:url output:output complete:complate sender:_sender httpingExt:nil];
}

- (void) httping:(NSString*)url output:(id<CLSOutputDelegate>)output complate:(CLSHttpCompleteHandler)complate customFiled:(NSMutableDictionary*) customFiled{
    [CLSHttp start:url output:output complete:complate sender:_sender httpingExt:customFiled];
}
@end
