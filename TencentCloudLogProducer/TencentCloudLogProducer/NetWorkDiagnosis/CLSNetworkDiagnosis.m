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
    [CLSPing start:host size:size output:output complete:complete sender:_sender];
}
- (void)ping:(NSString*)host size:(NSUInteger)size output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete count:(NSInteger)count{
    [CLSPing start:host size:size output:output complete:complete sender:_sender count:count];
}

//tcpPing
- (void)tcpPing:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete{
    [CLSTcpPing start:host output:output complete:complete sender:_sender];
}
- (void)tcpPing:(NSString*)host port:(NSUInteger)port count:(NSInteger)count output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete{
    [CLSTcpPing start:host port:port count:count output:output complete:complete sender:_sender];
}
//
//traceroute
- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete{
    [CLSTraceRoute start:host output:output complete:complete sender:_sender];
}

- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete maxTtl:(NSInteger)maxTtl{
    [CLSTraceRoute start:host output:output complete:complete sender:_sender maxTtl:maxTtl];
}

@end
