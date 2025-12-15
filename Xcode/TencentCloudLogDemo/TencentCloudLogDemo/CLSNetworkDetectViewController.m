#import "CLSNetworkDetectViewController.h"
#import <Foundation/Foundation.h>
#import "TencentCloudLogProducer/ClsNetworkDiagnosis.h"

@interface CLSNetworkDetectViewController ()

@end

@implementation CLSNetworkDetectViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"网络探测";
    
    // 按钮配置数组
    NSArray *btnTitles = @[@"httpping", @"tcpping", @"ping", @"mtr", @"dns"];
    CGFloat btnY = 100;
    CGFloat btnHeight = 50;
    CGFloat btnWidth = self.view.bounds.size.width - 100;
    CGFloat marginY = 20;
    
    // 批量创建按钮
    for (NSInteger i = 0; i < btnTitles.count; i++) {
        UIButton *detectBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        detectBtn.frame = CGRectMake(50, btnY + (btnHeight + marginY) * i, btnWidth, btnHeight);
        [detectBtn setTitle:btnTitles[i] forState:UIControlStateNormal];
        [detectBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        detectBtn.tag = 100 + i; // 标记按钮，区分点击事件
        [detectBtn addTarget:self action:@selector(networkDetectBtnClick:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:detectBtn];
    }
    
    //初始化网络探测发送接口
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou-open.cls.tencentcs.com"
                                                      accessKeyId:@""
                                                        accessKey:@""];
    [[ClsNetworkDiagnosis sharedInstance] setupLogSenderWithConfig:config topicId:nil netToken:@""];
}

- (void)networkDetectBtnClick:(UIButton *)sender {
    NSString *detectType = @"";
    switch (sender.tag) {
        case 100:
            detectType = @"httpping";
            [self callHttppingAPI];
            break;
        case 101:
            detectType = @"tcpping";
            [self callTcppingAPI];
            break;
        case 102:
            detectType = @"ping";
            [self callPingAPI];
            break;
        case 103:
            detectType = @"mtr";
            [self callMtrAPI];
            break;
        case 104:
            detectType = @"dns";
            [self callDnsAPI];
            break;
        default:
            break;
    }
    NSLog(@"开始执行%@探测", detectType);
}

#pragma mark - 各网络探测接口调用
- (void)callHttppingAPI {
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.detectEx = @{@"key1":@"value1"};
    request.userEx = @{@"key2":@"valuoe2"};
    request.domain = @"https://sa-saopaulo.cls.tencentcs.com/ping";
    [[ClsNetworkDiagnosis sharedInstance] httpingv2: request complate:^(CLSResponse *result){
        NSLog(@"%@",result);
    }];
}

- (void)callTcppingAPI {
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.detectEx = @{@"key1":@"value1"};
    request.userEx = @{@"key2":@"valuoe2"};
    request.domain = @"127.0.0.1";
    request.port = 80;
    [[ClsNetworkDiagnosis sharedInstance] tcpPingv2:request complate:^(CLSResponse *result){
        NSLog(@"result:%@",result);
    }];
}

- (void)callPingAPI {
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.detectEx = @{@"key1":@"value1"};
    request.userEx = @{@"key2":@"valuoe2"};
    request.domain = @"127.0.0.1";
    [[ClsNetworkDiagnosis sharedInstance] pingv2:request complate:^(CLSResponse *result){
        NSLog(@"result:%@",result);
    }];
}

- (void)callMtrAPI {
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.detectEx = @{@"key1":@"value1"};
    request.userEx = @{@"key2":@"valuoe2"};
    [[ClsNetworkDiagnosis sharedInstance] mtr:request complate:^(CLSResponse *result){
        NSLog(@"result:%@",result);
    }];
}

- (void)callDnsAPI {
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.detectEx = @{@"key1":@"value1"};
    request.userEx = @{@"key2":@"valuoe2"};
    [[ClsNetworkDiagnosis sharedInstance] dns:request complate:^(CLSResponse *result){
        NSLog(@"result:%@",result);
    }];
}

@end
