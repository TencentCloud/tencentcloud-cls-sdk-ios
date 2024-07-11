#import "CLSHttping.h"
#import <arpa/inet.h>
#import <netdb.h>
#import <netinet/in.h>

@implementation CLSHttpResult


- (NSString *)description {
    int contentLength = 0;
    NSString *strHeaders = @"-";
    NSDictionary *headers = [_response allHeaderFields];
    if (headers != nil){
        NSString *strContentLen = [headers objectForKey:@"Content-Length"];
        if ([strContentLen length] != 0){
            contentLength = [strContentLen intValue];
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:headers options:NSJSONWritingPrettyPrinted error:nil];
        strHeaders = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    NSDictionary *result = @{
                           @"method":@"httping",
                           @"url":_url,
                           @"requestTime":[NSString stringWithFormat:@"%.3f", _requestTime],
                           @"httpcode":[NSString stringWithFormat:@"%d", _response.statusCode],
                           @"contentLength":[NSString stringWithFormat:@"%d", contentLength],
                           @"errorMessage":_errMessage,
                           @"headers":strHeaders
                           };
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (instancetype)init:(NSString *)url
         requestTime:(NSTimeInterval)requestTime
response:(NSHTTPURLResponse *)response
             httpErr:(NSError*)httpErr{
    if (self = [super init]) {
        _url = url;
        _requestTime = requestTime;
        _response =response;
    }
    _errMessage = @"OK";
    if (httpErr != nil){
        _errMessage = [httpErr localizedDescription];
    }

    return self;
}

- (CLSHttpResult *)buildResult:(NSInteger)code
                            ip:(NSString *)ip
                            domain:(NSString *)domain
                     durations:(NSTimeInterval *)durations
                         count:(NSInteger)count
                          loss:(NSInteger)loss
                     totalTime:(NSTimeInterval)time {
    return nil;
}

@end

@interface CLSHttp ()
@property (readonly) NSString *url;
@property (readonly) id<CLSOutputDelegate> output;
@property (readonly) CLSHttpCompleteHandler complete;

@end

@implementation CLSHttp

- (instancetype)init:(NSString *)url
              output:(id<CLSOutputDelegate>)output
            complete:(CLSHttpCompleteHandler)complete
              sender: (baseSender *)sender
          httpingExt: (NSMutableDictionary*) httpingExt{
    if (self = [super init]) {
        _url = url;
        _output = output;
        _complete = complete;
        _sender = sender;
        _httpingExt = httpingExt;
    }
    return self;
}

- (NSString *)reserveUrlToIp {
    NSString *ip = nil;
    NSURL *url = [NSURL URLWithString:_url];
    NSString *domain = url.host;
    if (domain == nil) {
        domain = @"";
    }
    const char *d = [domain UTF8String];
    if (d == NULL) {
        d = "\0";
    }
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(80);
    addr.sin_addr.s_addr = inet_addr(d);
    if (addr.sin_addr.s_addr == INADDR_NONE) {
        struct hostent *host = gethostbyname(d);
        if (host == NULL || host->h_addr == NULL) {
            return ip;
        }
        addr.sin_addr = *(struct in_addr *)host->h_addr;
        ip = [NSString stringWithUTF8String:inet_ntoa(addr.sin_addr)];
    }
    return ip;
}

- (void)run {
    if (_output) {
        [_output write:[NSString stringWithFormat:@"GET %@", _url]];
    }

    NSDate *t1 = [NSDate date];
    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_url]];
    [urlRequest setHTTPMethod:@"GET"];

    NSHTTPURLResponse *response = nil;
    NSError *httpError = nil;
    NSData *d = [NSURLConnection sendSynchronousRequest:urlRequest
                                      returningResponse:&response
                                                  error:&httpError];
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:t1]*1000;
    if (_output) {
        if (httpError != nil) {
            [_output write:[httpError description]];
        }
        [_output write:[NSString stringWithFormat:@"complete duration:%f status %ld\n", duration, (long)response.statusCode]];
        if (response != nil && response.allHeaderFields != nil) {
            [response.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *obj, BOOL *stop) {
                [_output write:[NSString stringWithFormat:@"%@: %@\n", key, obj]];
            }];
        }
    }

    CLSHttpResult *result = [[CLSHttpResult alloc] init:_url requestTime:duration response:response httpErr:httpError];
    if (_complete != nil) {
        _complete(result);
    }
    [_sender report:result.description method:@"httping" domain:_url customFiled:_httpingExt];
}

+ (instancetype)start:(NSString *)url
               output:(id<CLSOutputDelegate>)output
             complete:(CLSHttpCompleteHandler)complete
               sender: (baseSender *)sender
           httpingExt: (NSMutableDictionary*) httpingExt
{
    if (url == nil) {
        url = @"";
    }
    CLSHttp *http = [[CLSHttp alloc] init:url output:output complete:complete sender:sender httpingExt:httpingExt];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        [http run];
    });
    return http;
}

- (void)stop {
}

@end
