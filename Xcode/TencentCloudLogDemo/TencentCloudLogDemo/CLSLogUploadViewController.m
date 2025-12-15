#import "CLSLogUploadViewController.h"
#import <Foundation/Foundation.h>
#import "TencentCloudLogProducer/ClsLogSender.h"
#import "TencentCloudLogProducer/CLSLogStorage.h"

@interface CLSLogUploadViewController ()
@property(nonatomic, strong) LogSender *sender;
@end

@implementation CLSLogUploadViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"日志上传";
    
    //初始化sender
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@""
                                                      accessKeyId:@""
                                                        accessKey:@""];
    _sender = [LogSender sharedSender];
    [_sender setConfig:config];
    [_sender start];
    
    // 发送日志按钮
    UIButton *sendLogBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    sendLogBtn.frame = CGRectMake(50, 150, self.view.bounds.size.width - 100, 50);
    [sendLogBtn setTitle:@"发送日志" forState:UIControlStateNormal];
    [sendLogBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [sendLogBtn addTarget:self action:@selector(sendLogBtnClick) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:sendLogBtn];
}

- (void)sendLogBtnClick {
    // 调用服务端上传日志接口
    [self uploadLogToServer];
}

- (void)uploadLogToServer {
    // 写入日志（自动触发发送）
    // 压缩后的 JSON 字符串（无缩进无换行）
    __block NSInteger logIndex = 0; // 自增序号（标记写入顺序）

    // 循环写入 10 条日志
    for (int i = 0; i < 1000; i++) {
        NSString *timestamp = [NSString stringWithFormat:@"%lld", (long long)([[NSDate date] timeIntervalSince1970] * 1000)];
        NSString *jsonString = [NSString stringWithFormat:@"{\"log_index\":\" %ld\",\"write_timestamp\":\"%@\"}",(long)i, timestamp];
        Log_Content *content = [Log_Content message];
        content.key = @"message";
        content.value = jsonString;
        
        Log *logItem = [Log message];
             [logItem.contentsArray addObject:content];
             logItem.time = [timestamp longLongValue]; // 日志时间戳（与写入时间一致）
        
        [[ClsLogStorage sharedInstance] writeLog:logItem
                                         topicId:@"topicid"
                                       completion:^(BOOL success, NSError *error) {
            if (success) {
                NSLog(@"日志写入成功（第 %d 条），等待发送", i + 1);
            } else {
                NSLog(@"日志写入失败（第 %d 条），error: %@", i + 1, error);
            }
        }];
    }

//    [[ClsLogStorage sharedInstance] writeLog:logItem
//                                     topicId:@"topicid"  // 与发送器绑定的主题一致
//                                   completion:^(BOOL success, NSError *error) {
//        if (success) {
//            NSLog(@"日志写入成功，等待发送");
//        }else{
//            NSLog(@"日志写入失败，error:%@",error);
//        }
//    }];
}

// 获取本地日志内容（示例方法，替换为实际获取逻辑）
- (NSString *)getLocalLogContent {
    // 此处仅为示例，实际需读取本地日志文件/缓存的日志内容
    return @"[2025-12-05 10:00:00] App启动成功\n[2025-12-05 10:05:00] 用户点击日志上传按钮";
}

// 弹窗提示
- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
