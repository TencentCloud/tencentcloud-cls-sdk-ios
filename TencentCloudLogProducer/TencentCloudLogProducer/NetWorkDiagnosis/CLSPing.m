//
//  CLSPing.m
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import "CLSPing.h"
#import "CLSQueue.h"

#import <arpa/inet.h>
#import <netdb.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>

#import <netinet/in.h>
#import <netinet/tcp.h>

#include <AssertMacros.h>
const int kCLSInvalidPingResponse = -22001;

@implementation CLSPingResult

struct Result{
    NSString *method;
    NSString *hostIP;
    NSString *host;
    NSInteger port;
    NSTimeInterval max;
    NSTimeInterval min;
    NSTimeInterval avg;
    NSTimeInterval stddev;
    double loss;
    NSInteger count;
};

- (NSString *)description {
    struct Result result;
    if (_code == 0 || _code == kCLSRequestStoped) {
        NSDictionary *result = @{
                               @"method":@"PING",
                               @"ip":_ip,
                               @"host":_domain,
                               @"max":[NSString stringWithFormat:@"%.3f", _maxRtt],
                               @"min":[NSString stringWithFormat:@"%.3f", _minRtt],
                               @"avg":[NSString stringWithFormat:@"%.3f", _avgRtt],
                               @"stddev":[NSString stringWithFormat:@"%.3f", _stddev],
                               @"size":[NSString stringWithFormat:@"%d", _size],
                               @"loss":[NSString stringWithFormat:@"%.3f", (double)_loss * 100 / (_count)],
                               @"count":[NSString stringWithFormat:@"%d", (int)(_count)],
                               @"dns":[CLSUtils GetDNSServers],
                               @"responseNum":[NSString stringWithFormat:@"%d", (int)(_count - _loss)]
                               };
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return [NSString stringWithFormat:@"ping failed %@", _err_msg];
}

- (instancetype)init:(NSInteger)code
             err_msg:(NSString*)err_msg
                  ip:(NSString *)ip
                  domain:(NSString *)domain
                size:(NSUInteger)size
                 max:(NSTimeInterval)maxRtt
                 min:(NSTimeInterval)minRtt
                 avg:(NSTimeInterval)avgRtt
                loss:(NSInteger)loss
               count:(NSInteger)count
           totalTime:(NSTimeInterval)totalTime
              stddev:(NSTimeInterval)stddev {
    if (self = [super init]) {
        _code = code;
        _err_msg = err_msg;
        _ip = ip;
        _domain = domain;
        _size = size;
        _minRtt = minRtt;
        _avgRtt = avgRtt;
        _maxRtt = maxRtt;
        _loss = loss;
        _totalTime = totalTime;
        _count = count;
        _stddev = stddev;
    }
    return self;
}

@end

struct IPHeader {
    uint8_t versionAndHeaderLength;
    uint8_t differentiatedServices;
    uint16_t totalLength;
    uint16_t identification;
    uint16_t flagsAndFragmentOffset;
    uint8_t timeToLive;
    uint8_t protocol;
    uint16_t headerChecksum;
    uint8_t sourceAddress[4];
    uint8_t destinationAddress[4];
    // options...
    // data...
};
typedef struct IPHeader IPHeader;

__Check_Compile_Time(sizeof(IPHeader) == 20);
__Check_Compile_Time(offsetof(IPHeader, versionAndHeaderLength) == 0);
__Check_Compile_Time(offsetof(IPHeader, differentiatedServices) == 1);
__Check_Compile_Time(offsetof(IPHeader, totalLength) == 2);
__Check_Compile_Time(offsetof(IPHeader, identification) == 4);
__Check_Compile_Time(offsetof(IPHeader, flagsAndFragmentOffset) == 6);
__Check_Compile_Time(offsetof(IPHeader, timeToLive) == 8);
__Check_Compile_Time(offsetof(IPHeader, protocol) == 9);
__Check_Compile_Time(offsetof(IPHeader, headerChecksum) == 10);
__Check_Compile_Time(offsetof(IPHeader, sourceAddress) == 12);
__Check_Compile_Time(offsetof(IPHeader, destinationAddress) == 16);

typedef struct ICMPPacket {
    uint8_t type;
    uint8_t code;
    uint16_t checksum;
    uint16_t identifier;
    uint16_t sequenceNumber;
    uint8_t payload[0]; // data, variable length
} ICMPPacket;

enum {
    kCLSICMPTypeEchoReply = 0,
    kCLSICMPTypeEchoRequest = 8
};

__Check_Compile_Time(sizeof(ICMPPacket) == 8);
__Check_Compile_Time(offsetof(ICMPPacket, type) == 0);
__Check_Compile_Time(offsetof(ICMPPacket, code) == 1);
__Check_Compile_Time(offsetof(ICMPPacket, checksum) == 2);
__Check_Compile_Time(offsetof(ICMPPacket, identifier) == 4);
__Check_Compile_Time(offsetof(ICMPPacket, sequenceNumber) == 6);

const int kCLSPacketSize = sizeof(ICMPPacket) + 100;

const int kCLSPacketBufferSize = 65535;

static uint16_t in_cksum(const void *buffer, size_t bufferLen)
// This is the standard BSD checksum code, modified to use modern types.
{
    size_t bytesLeft;
    int32_t sum;
    const uint16_t *cursor;
    union {
        uint16_t us;
        uint8_t uc[2];
    } last;
    uint16_t answer;

    bytesLeft = bufferLen;
    sum = 0;
    cursor = buffer;

    /*
     * Our algorithm is simple, using a 32 bit accumulator (sum), we add
     * sequential 16 bit words to it, and at the end, fold back all the
     * carry bits from the top 16 bits into the lower 16 bits.
     */
    while (bytesLeft > 1) {
        sum += *cursor;
        cursor += 1;
        bytesLeft -= 2;
    }

    /* mop up an odd byte, if necessary */
    if (bytesLeft == 1) {
        last.uc[0] = *(const uint8_t *)cursor;
        last.uc[1] = 0;
        sum += last.us;
    }

    /* add back carry outs from top 16 bits to low 16 bits */
    sum = (sum >> 16) + (sum & 0xffff); /* add hi 16 to low 16 */
    sum += (sum >> 16); /* add carry */
    answer = (uint16_t)~sum; /* truncate to 16 bits */

    return answer;
}

static ICMPPacket *build_packet(uint16_t seq, uint16_t identifier) {
    ICMPPacket *packet = (ICMPPacket *)calloc(kCLSPacketSize, 1);

    packet->type = kCLSICMPTypeEchoRequest; //设置回显请求报文
    packet->code = 0;
    packet->checksum = 0;
    packet->identifier = OSSwapHostToBigInt16(identifier); //标识符
    packet->sequenceNumber = OSSwapHostToBigInt16(seq);
    snprintf((char *)packet->payload, kCLSPacketSize - sizeof(ICMPPacket), "clslog ping test %d", (int)seq);
    packet->checksum = in_cksum(packet, kCLSPacketSize);
    return packet;
}

static char *icmpInPacket(char *packet, int len) {
    if (len < (sizeof(IPHeader) + sizeof(ICMPPacket))) {
        return NULL;
    }
    const struct IPHeader *ipPtr = (const IPHeader *)packet;
    if ((ipPtr->versionAndHeaderLength & 0xF0) != 0x40 // IPv4
        ||
        ipPtr->protocol != 1) { //ICMP
        return NULL;
    }
    size_t ipHeaderLength = (ipPtr->versionAndHeaderLength & 0x0F) * sizeof(uint32_t);

    if (len < ipHeaderLength + sizeof(ICMPPacket)) {
        return NULL;
    }

    return (char *)packet + ipHeaderLength;
}

static BOOL isValidResponse(char *buffer, int len, int seq, int identifier) {
    ICMPPacket *icmpPtr = (ICMPPacket *)icmpInPacket(buffer, len);
    if (icmpPtr == NULL) {
        return NO;
    }
    uint16_t receivedChecksum = icmpPtr->checksum;
    icmpPtr->checksum = 0;
    uint16_t calculatedChecksum = in_cksum(icmpPtr, len - ((char *)icmpPtr - buffer));

    return receivedChecksum == calculatedChecksum &&
           icmpPtr->type == kCLSICMPTypeEchoReply &&
           icmpPtr->code == 0 &&
           OSSwapBigToHostInt16(icmpPtr->identifier) == identifier &&
           OSSwapBigToHostInt16(icmpPtr->sequenceNumber) <= seq;
}


@implementation CLSPing
- (int)sendPacket:(ICMPPacket *)packet
             sock:(int)sock
           target:(struct sockaddr_in *)addr {
    if (_size < 100) {
        _size = 100;
    } else if (_size > 1400) {
        _size = 1400;
    }
    ssize_t sent = sendto(sock, packet, (size_t)_size, 0, (struct sockaddr *)addr, (socklen_t)sizeof(struct sockaddr));
    if (sent < 0) {
        return errno;
    }
    return 0;
}

- (int)ping:(struct sockaddr_in *)addr
        seq:(uint16_t)seq
 identifier:(uint16_t)identifier
       sock:(int)sock
        ttl:(int *)ttlOut
       size:(int *)size {
    ICMPPacket *packet = build_packet(seq, identifier);
    int err = 0;
    err = [self sendPacket:packet sock:sock target:addr];
    free(packet);
    if (err != 0) {
        return err;
    }

    struct sockaddr_storage ret_addr;
    socklen_t addrLen = sizeof(ret_addr);
    ;
    void *buffer = malloc(kCLSPacketBufferSize);

    ssize_t bytesRead = recvfrom(sock, buffer, kCLSPacketBufferSize, 0,
                                 (struct sockaddr *)&ret_addr, &addrLen);
    if (bytesRead < 0) {
        err = errno;
    } else if (bytesRead == 0) {
        err = EPIPE;
    } else {
        if (isValidResponse(buffer, (int)bytesRead, seq, identifier)) {
            *ttlOut = ((IPHeader *)buffer)->timeToLive;
            *size = (int)bytesRead;
        } else {
            err = kCLSInvalidPingResponse;
        }
    }
    free(buffer);
    return err;
}

- (CLSPingResult *)buildResult:(NSInteger)code
                            ip:(NSString *)ip
                            domain:(NSString *)domain
                     durations:(NSTimeInterval *)durations
                         count:(NSInteger)count
                          loss:(NSInteger)loss
                     totalTime:(NSTimeInterval)time {
    if (code != 0 && code != kCLSRequestStoped) {
        return [[CLSPingResult alloc] init:code err_msg:@"timeout" ip:ip domain:domain size:_size max:0 min:0 avg:0 loss:1 count:1 totalTime:time stddev:0];
    }
    NSTimeInterval max = 0;
    NSTimeInterval min = 10000000;
    NSTimeInterval sum = 0;
    NSTimeInterval sum2 = 0;
    for (int i = 0; i < count; i++) {
        if (durations[i] > max) {
            max = durations[i];
        }
        if (durations[i] < min) {
            min = durations[i];
        }
        sum += durations[i];
        sum2 += durations[i] * durations[i];
    }
    NSTimeInterval avg = sum / count;
    NSTimeInterval avg2 = sum2 / count;
    NSTimeInterval stddev = sqrt(avg2 - avg * avg);
    return [[CLSPingResult alloc] init:code err_msg:@"ping success" ip:ip domain:domain size:_size max:max min:min avg:avg loss:loss count:count totalTime:time stddev:stddev];
}

- (void)run{
    
    const char *hostaddr = [_host UTF8String];
    if (hostaddr == NULL) {
        hostaddr = "\0";
    }

    NSDate *begin = [NSDate date];
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(30002);
    addr.sin_addr.s_addr = inet_addr(hostaddr);

    if (addr.sin_addr.s_addr == INADDR_NONE) { //无效的地址
        struct hostent *host = gethostbyname(hostaddr);
        if (host == NULL || host->h_addr == NULL) {
            [self.output write:@"host illegal exit"];
            if (_complete != nil && !_stopped) {
                [CLSQueue async_run_main:^(void) {
                    CLSPingResult *result = [[CLSPingResult alloc] init:-1006 err_msg:@"host illegal" ip:nil domain:_host size:_size max:0 min:0 avg:0 loss:0 count:0 totalTime:0 stddev:0];
                    _complete(result);
                }];
                [_sender report:[[CLSPingResult alloc] init:-1006 err_msg:@"host illegal" ip:nil domain:_host size:_size max:0 min:0 avg:0 loss:0 count:0 totalTime:0 stddev:0].description method:@"ping" domain:_host];
            }
            return;
        }
        addr.sin_addr = *(struct in_addr *)host->h_addr;
        [self.output write:[NSString stringWithFormat:@"ping to ip %s ...\n", inet_ntoa(addr.sin_addr)]];
    }

    NSTimeInterval *durations = (NSTimeInterval *)calloc(sizeof(NSTimeInterval) * _count, 1);
    int index = 0;
    int r = 0;
    uint16_t identifier = (uint16_t)arc4random();
    int ttl = 0;
    int size = 0;
    int loss = 0;
    do {
        NSDate *t1 = [NSDate date];
        int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
        struct timeval timeout;
        timeout.tv_sec = 10;
        timeout.tv_usec = 0;
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout));
        r = [self ping:&addr seq:index identifier:identifier sock:sock ttl:&ttl size:&size];
        NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:t1];
        if (r == 0) {
            // ignore broadcast address
            [self.output write:[NSString stringWithFormat:@"%d bytes from %s: icmp_seq=%ld ttl=%d time=%f ms\n", size, inet_ntoa(addr.sin_addr), (long)index, ttl, duration * 1000]];
            durations[index - loss] = duration * 1000;
        } else {
            [self.output write:[NSString stringWithFormat:@"Request timeout for icmp_seq %ld\n", (long)index]];
            loss++;
        }

        if (index < _count && !_stopped) {
            [NSThread sleepForTimeInterval:0.1];
        }
        close(sock);
    } while (++index < _count && !_stopped);
    NSInteger code = r;
    if (_stopped) {
        code = kCLSRequestStoped;
    }
    if (_complete && !_stopped ) {
        CLSPingResult *result = [self buildResult:code ip:[NSString stringWithUTF8String:inet_ntoa(addr.sin_addr)]
                                           domain:_host
                                        durations:durations
                                            count:index
                                             loss:loss
                                        totalTime:[[NSDate date] timeIntervalSinceDate:begin] * 1000];
        [self.output write:result.description];
        [CLSQueue async_run_main:^(void) {
            _complete(result);
        }];
    }
    
    //发送数据到cls
    if (!_stopped){
        [_sender report:[self buildResult:r ip:[NSString stringWithUTF8String:inet_ntoa(addr.sin_addr)]
                                   domain:_host
                                durations:durations
                                    count:index
                                     loss:loss
                                totalTime:[[NSDate date] timeIntervalSinceDate:begin] * 1000].description method:@"PING" domain:_host];
    }

    free(durations);
}

- (instancetype)init:(NSString *)host
                size:(NSUInteger)size
              output:(id<CLSOutputDelegate>)output
            complete:(CLSPingCompleteHandler)complete
               count:(NSInteger)count
              sender: (baseSender *)sender{
    if (self = [super init]) {
        _host = host;
        _size = size;
        _output = output;
        _complete = complete;
        _count = count;
        _sender = sender;
    }
    return self;
}

+ (instancetype)start:(NSString *)host
                 size:(NSUInteger)size
               output:(id<CLSOutputDelegate>)output
             complete:(CLSPingCompleteHandler)complete
               sender: (baseSender *)sender{
    return [CLSPing start:host size:size task_timeout:60000 output:output complete:complete sender:sender  count:10];
}

+ (instancetype)start:(NSString *)host
                 size:(NSUInteger)size
         task_timeout:(NSUInteger)task_timeout
               output:(id<CLSOutputDelegate>)output
             complete:(CLSPingCompleteHandler)complete
               sender: (baseSender *)sender
                count:(NSInteger)count {
    if (host == nil) {
        host = @"";
    }
    
    CLSPing *ping = [[CLSPing alloc] init:host size:size output:output complete:complete count:count sender:sender];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        dispatch_semaphore_t mySemaphore = dispatch_semaphore_create(0);
        dispatch_time_t t_out = dispatch_time(DISPATCH_TIME_NOW, task_timeout * NSEC_PER_MSEC);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
            [ping run];
            dispatch_semaphore_signal(mySemaphore);
        });
        if (dispatch_semaphore_wait(mySemaphore, t_out) != 0) {
            [ping stop];
            if (complete != nil){
                complete([ping buildResult:kCLSTaskTimeOut ip:@"" domain:@"" durations:0 count:0 loss:0 totalTime:0]);
            }
        }
    });
    return ping;
}

- (void)stop {
    _stopped = YES;
    return;
}
@end
