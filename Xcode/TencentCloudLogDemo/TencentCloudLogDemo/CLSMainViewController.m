#import "CLSMainViewController.h"
#import "CLSLogUploadViewController.h"
#import "CLSNetworkDetectViewController.h"

@interface CLSMainViewController ()

@end

@implementation CLSMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"cls ios sdk";
    
    // 日志上传按钮
    UIButton *logUploadBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    logUploadBtn.frame = CGRectMake(50, 150, self.view.bounds.size.width - 100, 50);
    [logUploadBtn setTitle:@"日志上传" forState:UIControlStateNormal];
    [logUploadBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [logUploadBtn addTarget:self action:@selector(logUploadBtnClick) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:logUploadBtn];
    
    // 网络探测按钮
    UIButton *networkDetectBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    networkDetectBtn.frame = CGRectMake(50, 250, self.view.bounds.size.width - 100, 50);
    [networkDetectBtn setTitle:@"网络探测" forState:UIControlStateNormal];
    [networkDetectBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [networkDetectBtn addTarget:self action:@selector(networkDetectBtnClick) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:networkDetectBtn];
}

- (void)logUploadBtnClick {
    CLSLogUploadViewController *logVC = [[CLSLogUploadViewController alloc] init];
    [self.navigationController pushViewController:logVC animated:YES];
}

- (void)networkDetectBtnClick {
    CLSNetworkDetectViewController *networkVC = [[CLSNetworkDetectViewController alloc] init];
    [self.navigationController pushViewController:networkVC animated:YES];
}

@end
