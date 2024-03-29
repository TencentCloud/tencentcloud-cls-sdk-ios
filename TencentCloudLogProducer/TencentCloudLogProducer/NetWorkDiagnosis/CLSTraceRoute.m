//
//  CLSTraceRoute.m
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//
//CLSTraceRoute
#import "CLSTraceRoute.h"
#import <arpa/inet.h>
#import <netdb.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>

#import <netinet/in.h>
#import <netinet/tcp.h>

#import <sys/select.h>
#import <sys/time.h>

#import "CLSQueue.h"

@interface CLSTraceRouteRecord : NSObject
@property (readonly) NSInteger hop;
@property NSString* ip;
@property NSString* targetIp;
@property NSString* domain;
@property NSTimeInterval* durations; //ms
@property (readonly) NSInteger count; //ms
@end

@implementation CLSTraceRouteRecord

- (instancetype)init:(NSInteger)hop
              domain:(NSString*)domain
            targetIp:(NSString*)targetIp
               count:(NSInteger)count {
    if (self = [super init]) {
        _ip = nil;
        _hop = hop;
        _domain = domain;
        _durations = (NSTimeInterval*)calloc(count, sizeof(NSTimeInterval));
        _count = count;
        _targetIp = targetIp;
    }
    return self;
}

- (NSDictionary*)buildDirectRecord{
    NSError *error = nil;
//    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_contentString options:NSJSONWritingPrettyPrinted error:&error];
    NSString *ip = @" ";
    if (_ip != nil){
        ip = _ip;
    }
    bool is_final_route = false;
    NSInteger realCount = 0;
    NSInteger loss = 0;
    double avg = 0;
    double totalDelay = 0;
    for (int i = 0; i < _count; i++) {
        if (_durations[i] <= 0) {
            loss++;
            continue;
        } else {
            realCount++;
            totalDelay += _durations[i];
        }
    }
    double lossRate = loss/_count*100;
    if (_targetIp == ip){
        is_final_route = true;
    }
    NSDictionary *result = @{
        @"targetIp":_targetIp,
       @"routeIp":ip,
       @"hop":[NSString stringWithFormat:@"%d", (int)(_hop)],
        @"avg_delay":[NSString stringWithFormat:@"%.3f", avg],
        @"loss":[NSString stringWithFormat:@"%.3f",lossRate],
        @"dns":[CLSUtils GetDNSServers],
        @"is_final_route":@(is_final_route)
       };
    return result;
}

- (NSString*)description {
        NSData *data = [NSJSONSerialization dataWithJSONObject:[self buildDirectRecord] options:NSJSONWritingPrettyPrinted error:nil];
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (void)dealloc {
    free(_durations);
}
@end

@implementation CLSTraceRouteResult

- (instancetype)init:(NSInteger)code
                  ip:(NSString*)ip
             content:(NSString*)content {
    if (self = [super init]) {
        _code = code;
        _ip = ip;
        _content = content;
    }
    return self;
}

@end

@interface CLSTraceRoute ()
@property (readonly) NSString* host;
@property (readonly) NSString* targetIp;
@property (readonly) NSString* commandStatus;
@property (nonatomic, strong) id<CLSOutputDelegate> output;
@property (readonly) CLSTraceRouteCompleteHandler complete;
@property(nonatomic, strong) baseSender *sender;

@property (readonly) NSInteger maxTtl;
@property (atomic) NSInteger stopped;
@property (nonatomic, strong) NSMutableArray* contentString;

@end

@implementation CLSTraceRoute

- (instancetype)init:(NSString*)host
              output:(id<CLSOutputDelegate>)output
            complete:(CLSTraceRouteCompleteHandler)complete
              sender: (baseSender *)sender
              maxTtl:(NSInteger)maxTtl {
    if (self = [super init]) {
        _host = host == nil ? @"" : host;
        _output = output;
        _complete = complete;
        _maxTtl = maxTtl;
        _stopped = NO;
        _contentString = [[NSMutableArray alloc] init];
        _sender = sender;
        _targetIp = @"";
        _commandStatus = @"fail";
    }
    return self;
}

static const int TraceMaxAttempts = 3;

- (NSInteger)sendAndRecv:(int)sendSock
                    recv:(int)icmpSock
                    addr:(struct sockaddr_in*)addr
                     ttl:(int)ttl
                      ip:(in_addr_t*)ipOut {
    int err = 0;
    struct sockaddr_in storageAddr;
    socklen_t n = sizeof(struct sockaddr);
    static char cmsg[] = "clslog diag\n";
    char buff[100];

    CLSTraceRouteRecord* record = [[CLSTraceRouteRecord alloc] init:ttl domain:_host targetIp:_targetIp count:TraceMaxAttempts];
    for (int try = 0; try < TraceMaxAttempts; try ++) {
        NSDate* startTime = [NSDate date];
        ssize_t sent = sendto(sendSock, cmsg, sizeof(cmsg), 0, (struct sockaddr*)addr, sizeof(struct sockaddr));
        if (sent != sizeof(cmsg)) {
            err = errno;
            NSLog(@"error %s", strerror(err));
            [self.output write:[NSString stringWithFormat:@"send error %s\n", strerror(err)]];
            break;
        }

        struct timeval tv;
        fd_set readfds;
        tv.tv_sec = 3;
        tv.tv_usec = 0;
        FD_ZERO(&readfds);
        FD_SET(icmpSock, &readfds);
        select(icmpSock + 1, &readfds, NULL, NULL, &tv);
        if (FD_ISSET(icmpSock, &readfds) > 0) {
            ssize_t res = recvfrom(icmpSock, buff, sizeof(buff), 0, (struct sockaddr*)&storageAddr, &n);
            if (res < 0) {
                err = errno;
                [self.output write:[NSString stringWithFormat:@"recv error %s\n", strerror(err)]];
                break;
            } else {
                NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startTime];
                char ip[16] = {0};
                inet_ntop(AF_INET, &storageAddr.sin_addr.s_addr, ip, sizeof(ip));
                *ipOut = storageAddr.sin_addr.s_addr;
                NSString* remoteAddress = [NSString stringWithFormat:@"%s", ip];
                record.ip = remoteAddress;
                record.durations[try] = duration;
            }
        }

        if (_stopped) {
            break;
        }
    }
    [_output write:[NSString stringWithFormat:@"%@\n", record]];
    [_contentString addObject:[record buildDirectRecord]];

    return err;
}

- (void)run {
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(30002);
    const char* hostaddr = [_host UTF8String];
    if (hostaddr == NULL) {
        hostaddr = "\0";
    }
    addr.sin_addr.s_addr = inet_addr(hostaddr);
    [self.output write:[NSString stringWithFormat:@"traceroute to %@ ...\n", _host]];
    if (addr.sin_addr.s_addr == INADDR_NONE) {
        struct hostent* host = gethostbyname(hostaddr);
        if (host == NULL || host->h_addr == NULL) {
            [self.output write:@"Problem accessing the DNS"];
            if (_complete != nil) {
                [CLSQueue async_run_main:^(void) {
                    CLSTraceRouteResult* result = [[CLSTraceRouteResult alloc] init:-1006 ip:nil content:@"Problem accessing the DNS"];
                    _complete(result);
                }];
                [_sender report:@"Problem accessing the DNS" method:@"traceRoute" domain:_host];
            }
            return;
        }
        addr.sin_addr = *(struct in_addr*)host->h_addr;
        [self.output write:[NSString stringWithFormat:@"traceroute to ip %s ...\n", inet_ntoa(addr.sin_addr)]];
        _targetIp = [NSString stringWithUTF8String:inet_ntoa(addr.sin_addr)];
    }else{
        _targetIp =_host;
    }

    int recv_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    if (-1 == fcntl(recv_sock, F_SETFL, O_NONBLOCK)) {
        NSLog(@"fcntl socket error!");
        if (_complete != nil) {
            [CLSQueue async_run_main:^(void) {
                CLSTraceRouteResult* result = [[CLSTraceRouteResult alloc] init:-1 ip:[NSString stringWithUTF8String:inet_ntoa(addr.sin_addr)] content:nil];
                _complete(result);
            }];
            [_sender report:@"fcntl socket error!" method:@"traceRoute" domain:_host];
        }
        close(recv_sock);
        return;
    }

    int send_sock = socket(AF_INET, SOCK_DGRAM, 0);

    int ttl = 1;
    in_addr_t ip = 0;
    NSDate* startDate = [NSDate date];
    do {
        int t = setsockopt(send_sock, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl));
        if (t < 0) {
            NSLog(@"errro %s\n", strerror(t));
        }
        [self sendAndRecv:send_sock recv:recv_sock addr:&addr ttl:ttl ip:&ip];
    } while (++ttl <= _maxTtl && !_stopped && ip != addr.sin_addr.s_addr);
    close(send_sock);
    close(recv_sock);
    if (ip == addr.sin_addr.s_addr){
        _commandStatus = @"success";
    }
    NSInteger code = 0;
    if (_stopped) {
        code = kCLSRequestStoped;
    }
    if (_complete != nil){
        [CLSQueue async_run_main:^(void) {
            CLSTraceRouteResult* result = [[CLSTraceRouteResult alloc] init:code ip:[NSString stringWithUTF8String:inet_ntoa(addr.sin_addr)] content:_contentString];
            _complete(result);
        }];
    }


    [_sender report:[self buildResult]method:@"traceRoute" domain:_host];
}

- (NSDictionary*)buildResult{
    NSDictionary *result = @{
        @"host":_host,
       @"host_ip":_targetIp,
       @"command_status":_commandStatus,
        @"traceroute_node_results":_contentString
       };
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:&error];
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] ;
}

+ (instancetype)start:(NSString*)host
               output:(id<CLSOutputDelegate>)output
             complete:(CLSTraceRouteCompleteHandler)complete
               sender: (baseSender *)sender{
    return [CLSTraceRoute start:host output:output complete:complete sender:sender maxTtl:64];
}

+ (instancetype)start:(NSString*)host
               output:(id<CLSOutputDelegate>)output
             complete:(CLSTraceRouteCompleteHandler)complete
               sender: (baseSender *)sender
               maxTtl:(NSInteger)maxTtl {
    CLSTraceRoute* t = [[CLSTraceRoute alloc] init:host output:output complete:complete sender:sender maxTtl:maxTtl];

    [CLSQueue async_run_serial:^(void) {
        [t run];
    }];

    return t;
}

- (void)stop {
    _stopped = YES;
}
@end
