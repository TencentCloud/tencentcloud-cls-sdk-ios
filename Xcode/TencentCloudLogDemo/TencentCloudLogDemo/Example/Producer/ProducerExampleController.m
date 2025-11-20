

#import "ProducerExampleController.h"
#import "TencentCloudLogProducer/ClsLogSender.h"
#import "TencentCloudLogProducer/CLSLogStorage.h"

@interface ProducerExampleController ()
@property(nonatomic, strong) UITextView *statusTextView;
@property(nonatomic, strong) LogSender *sender;

@end

@implementation ProducerExampleController

static ProducerExampleController *selfClzz;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    selfClzz = self;
    self.title = @"基础信息配置";
    [self initViews];
    [self initLogProducer];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [[LogSender sharedSender] stop]; // 应用退出前停止日志发送线程
}

- (void) initViews {
    self.view.backgroundColor = [UIColor whiteColor];
    [self createLabel:@"参数: " andX:0 andY:0];

    DemoUtils *utils = [DemoUtils sharedInstance];
    NSString *parameters = [NSString stringWithFormat:@"endpoint: %@\ntopic: %@\naccessKeyId: %@\naccesskeySecret: %@\n",
                            utils.endpoint,
                            utils.topic,
                            utils.accessKeyId,
                            utils.accessKeySecret];
    
    UILabel *label = [self createLabel:parameters andX:0 andY:SLCellHeight andWidth:CLScreenW - SLPadding * 2 andHeight:SLCellHeight * 5];
    label.numberOfLines = 0;
    [label sizeToFit];
    label.textAlignment = NSTextAlignmentLeft;
    
    [self createLabel:@"结果: " andX:0 andY:SLCellHeight * 5];
    
    self.statusTextView = [self createTextView:@"" andX:0 andY:SLCellHeight * 6 andWidth:(CLScreenW - SLPadding * 2) andHeight:(SLCellHeight * 4)];
    self.statusTextView.textAlignment = NSTextAlignmentLeft;
    self.statusTextView.layoutManager.allowsNonContiguousLayout = NO;
    [self.statusTextView setEditable:NO];
    [self.statusTextView setContentOffset:CGPointMake(0, 0)];
    
    [self createButton:@"发送" andAction:@selector(send) andX:((CLScreenW - SLPadding * 2 - SLCellWidth) / 2) andY:SLCellHeight * 11];
}

- (void) UpdateReult: (NSString *)append {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *status = [NSString stringWithFormat:@"%@\n> %@", self.statusTextView.text, append];
        [self.statusTextView setText:status];
        [self.statusTextView scrollRangeToVisible:NSMakeRange(self->_statusTextView.text.length, 1)];
    });
}

- (void) send{
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
- (void) initLogProducer {
    DemoUtils *utils = [DemoUtils sharedInstance];
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:[utils endpoint]
                                                      accessKeyId:[utils accessKeyId]
                                                        accessKey:[utils accessKeySecret]];
    _sender = [LogSender sharedSender];
    [_sender setConfig:config];
    [_sender start];
}


@end
