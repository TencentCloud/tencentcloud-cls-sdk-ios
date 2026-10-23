
#import <XCTest/XCTest.h>
#import <TencentCloudLogProducer/CLSNetworkUtils.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <signal.h>

static uint16_t ClsStartHostileServer(dispatch_block_t * _Nullable outStopper) {
    int listenFd = socket(AF_INET, SOCK_STREAM, 0);
    if (listenFd < 0) return 0;

    int reuse = 1;
    setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0; // 让 kernel 挑端口

    if (bind(listenFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(listenFd);
        return 0;
    }
    socklen_t len = sizeof(addr);
    if (getsockname(listenFd, (struct sockaddr *)&addr, &len) < 0) {
        close(listenFd);
        return 0;
    }
    if (listen(listenFd, 4) < 0) {
        close(listenFd);
        return 0;
    }

    __block BOOL stop = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        while (!stop) {
            struct sockaddr_in client;
            socklen_t clen = sizeof(client);
            int c = accept(listenFd, (struct sockaddr *)&client, &clen);
            if (c < 0) {
                if (stop) break;
                continue;
            }
            close(c);
        }
        close(listenFd);
    });

    if (outStopper) {
        *outStopper = ^{
            stop = YES;
            int wake = socket(AF_INET, SOCK_STREAM, 0);
            if (wake >= 0) {
                connect(wake, (struct sockaddr *)&addr, sizeof(addr));
                close(wake);
            }
        };
    }
    return ntohs(addr.sin_port);
}

@interface CLSSigPipeTests : XCTestCase
@end

@implementation CLSSigPipeTests

- (void)testGeoRequest_PeerImmediatelyCloses_DoesNotCrashProcess {
    dispatch_block_t stopper = nil;
    uint16_t port = ClsStartHostileServer(&stopper);
    XCTAssertGreaterThan(port, 0, @"failed to start local hostile TCP server");

    NSString *endpoint = [NSString stringWithFormat:@"http://127.0.0.1:%u", port];

    XCTestExpectation *done = [self expectationWithDescription:@"geo call returns"];
    __block NSDictionary *result = nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        result = [CLSNetworkUtils getNetworkEnvironmentInfo:@"wifi"
                                               networkAppId:@"nid"
                                                     appKey:@"key"
                                                        uin:@"1"
                                                   endpoint:endpoint
                                              interfaceName:nil];
        [done fulfill];
    });
    [self waitForExpectationsWithTimeout:10.0 handler:^(NSError *err) {
        if (err) XCTFail(@"GEO call did not return in time; possible deadlock or SIGPIPE");
    }];

    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result, @{}, @"peer-closed GEO request should degrade to empty dict");

    if (stopper) stopper();
}

- (void)testGeoRequest_PeerImmediatelyCloses_MultipleTimes_StillAlive {
    dispatch_block_t stopper = nil;
    uint16_t port = ClsStartHostileServer(&stopper);
    XCTAssertGreaterThan(port, 0);
    NSString *endpoint = [NSString stringWithFormat:@"http://127.0.0.1:%u", port];

    for (int i = 0; i < 5; i++) {
        NSDictionary *d = [CLSNetworkUtils getNetworkEnvironmentInfo:@"wifi"
                                                        networkAppId:@"nid"
                                                              appKey:@"key"
                                                                 uin:@"1"
                                                            endpoint:endpoint
                                                       interfaceName:nil];
        XCTAssertEqualObjects(d, @{}, @"iteration %d should return empty dict", i);
    }
    if (stopper) stopper();
}

@end
