//
//  ProducerExampleNetDiaController.m
//  TencentCloundLogDemo
//
//  Created by herrylv on 2022/6/8.
//

#import "ProducerExampleNetDiaController.h"
#import "CLSNetworkDiagnosis.h"
#import "CLSAdapter.h"
#import "CLSNetDiag.h"

@interface CLSWriter : NSObject<CLSOutputDelegate>
@property(nonatomic,copy)NSString *host;
@end

@implementation CLSWriter

- (void)write:(NSString *)line {
    NSLog(@"CLSWriter output:%@",line);
}
@end

@interface ProducerExampleNetDiaController ()
@property(nonatomic, strong) UITextView *statusTextView;
@property (nonatomic, strong) NSMutableString* contentString;
@end

@implementation ProducerExampleNetDiaController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.title = @"网络探测";
    _contentString = [[NSMutableString alloc] init];
    [self initViews];
    [self startNetWork];
}

- (void) initViews {
    self.view.backgroundColor = [UIColor whiteColor];
    [self createLabel:@"探测中..." andX:0 andY:0];
    
    self.statusTextView = [self createTextView:@"" andX:0 andY:SLCellHeight * 1 andWidth:(CLScreenW - SLPadding * 2) andHeight:(SLCellHeight * 12)];
    self.statusTextView.textAlignment = NSTextAlignmentLeft;
    self.statusTextView.layoutManager.allowsNonContiguousLayout = NO;
    [self.statusTextView setEditable:NO];
    [self.statusTextView setContentOffset:CGPointMake(0, 0)];
    
}

- (void) UpdateReult: (NSString *)append {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *status = [NSString stringWithFormat:@"%@\n> %@", self.statusTextView.text, append];
        [self.statusTextView setText:status];
        [self.statusTextView scrollRangeToVisible:NSMakeRange(self->_statusTextView.text.length, 1)];
    });
}

- (void) startNetWork {

    CLSConfig *config = [[CLSConfig alloc] init];
    [config setDebuggable:YES];

    [config setEndpoint: @"ap-guangzhou.cls.tencentcs.com"];
    [config setAccessKeyId: @""];
    [config setAccessKeySecret: @""];
    [config setTopicId:@""];
    [config setPluginAppId: @"your pluginid"];

    // 自定义参数
    [config setUserId:@"user1"];
    [config setChannel:@"channel1"];
    [config addCustomWithKey:@"customKey" andValue:@"testValue"];
    
    CLSAdapter *clsAdapter = [CLSAdapter sharedInstance];
    [clsAdapter addPlugin:[[CLSNetworkDiagnosisPlugin alloc] init]];
    [clsAdapter initWithCLSConfig:config];
    
    
//    [_contentString appendString:[NSString stringWithFormat:@"endpoint:%@\n", config.endpoint]];
    //ping
    [[CLSNetworkDiagnosis sharedInstance] ping:@"ap-guangzhou.cls.tencentcs.com" size:0 output:[[CLSWriter alloc] init] complete:^(CLSPingResult *result){
        [_contentString appendString:[NSString stringWithFormat:@"pingResult:%@\n", result.description]];
        [self UpdateReult:_contentString];
    }];
    //tcpPing
//    [[CLSNetworkDiagnosis sharedInstance] tcpPing:@"ap-guangzhou.cls.tencentcs.com" port :80 task_timeout:5000 count:10 output:[[CLSWriter alloc] init] complete:^(CLSTcpPingResult *result){
//        [_contentString appendString:[NSString stringWithFormat:@"tcpPingResult:%@\n", result.description]];
//        [self UpdateReult:_contentString];
//    }];
    
    //traceroute
//    [[CLSNetworkDiagnosis sharedInstance] traceRoute:@"ap-guangzhou.cls.tencentcs.com" output:[[CLSWriter alloc] init] complete:^(CLSTraceRouteResult *result){
//        [_contentString appendString:[NSString stringWithFormat:@"traceResult:%@\n", result.content]];
//        [self UpdateReult:_contentString];
//    }];
    
    //httping
//    [[CLSNetworkDiagnosis sharedInstance] httping:@"https://ap-guangzhou.cls.tencentcs.com/ping" output:[[CLSWriter alloc] init] complate:^(CLSHttpResult *result){
//        NSLog(result.description);
//        [_contentString appendString:[NSString stringWithFormat:@"httpResult:%@\n",result.description]];
//        [self UpdateReult:_contentString];
//    }];
}

@end
