

#import "ProducerExampleController.h"
#import "TencentCloudLogProducer/ClsLogProducerClient.h"

@interface ProducerExampleController ()
@property(nonatomic, strong) UITextView *statusTextView;
@property(nonatomic, strong) ClsLogProducerConfig *config;
@property(nonatomic, strong) ClsLogProducerClient *client;

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

    for (int i = 0; i < 10000; i++) {
        ClsLogProducerResult result = [_client PostClsLog:[self LogData]];
        if( result != ClsLogProducerOK){
            printf("addlog result: %d\n", result);
        }
       
    }
    
}

static void log_send_callback(const char * config_name, int result, size_t log_bytes, size_t compressed_bytes, const char * req_id, const char * message, const unsigned char * raw_buffer, void * userparams) {
    if (result == ClsLogProducerOK) {
        NSString *success = [NSString stringWithFormat:@"send success, topic : %s, result : %d, log bytes : %d, compressed bytes : %d, request id : %s", config_name, (result), (int)log_bytes, (int)compressed_bytes, req_id];
        CLSLogV("%@", success);
        
        [selfClzz UpdateReult:success];
    } else {
        NSString *fail = [NSString stringWithFormat:@"send fail   , topic : %s, result : %d, log bytes : %d, compressed bytes : %d, request id : %s, error message : %s", config_name, (result), (int)log_bytes, (int)compressed_bytes, req_id, message];
        CLSLogV("%@", fail);
        
        [selfClzz UpdateReult:fail];
    }
}

- (void) initLogProducer {
    DemoUtils *utils = [DemoUtils sharedInstance];

    _config = [[ClsLogProducerConfig alloc] initClsWithCoreInfo:[utils endpoint] accessKeyID:[utils accessKeyId] accessKeySecret:[utils accessKeySecret]];
    [_config SetClsTopic:utils.topic];
    [_config SetClsPackageLogBytes:1024*1024];
    [_config SetClsPackageLogCount:1024];
    [_config SetClsPackageTimeout:3000];
    [_config SetClsMaxBufferLimit:64*1024*1024];
    [_config SetClsSendThreadCount:1];
    [_config SetClsConnectTimeoutSec:10];
    [_config SetClsSendTimeoutSec:10];
    [_config SetClsDestroyFlusherWaitSec:1];
    [_config SetClsDestroySenderWaitSec:1];
    [_config SetClsCompressType:1];
    
    //如下支持checkpoint点位落盘机制
    [_config SetPersistent:0];
    NSArray  *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *Path = [[paths lastObject] stringByAppendingString:@"/cls.dat"];
    NSLog(@"文件路径：%@", Path);
    [_config SetPersistentFilePath:Path];
    [_config SetPersistentMaxFileCount:10];
    [_config SetPersistentMaxFileSize:1*1024*1024];
    [_config SetPersistentMaxLogCount:65536];

    _client = [[ClsLogProducerClient alloc] initWithClsLogProducer:_config callback:log_send_callback];
}


- (ClsLog *) LogData {
    ClsLog* log = [[ClsLog alloc] init];

    [log PutClsContent:@"content_key_1" value:@"1abcakjfhksfsfsxyz012345678!@#$%^&"];
    [log PutClsContent:@"content_key_2" value:@"2abcdefghijklmnopqrstuvwxyz4444444"];
    [log PutClsContent:@"content_key_3" value:@"3slfjhdfjh092834932hjksnfjknskjfnd"];
    [log PutClsContent:@"content_key_4" value:@"4slfjhdfjh092834932hjksnfjknskjfnd"];
    [log PutClsContent:@"content_key_5" value:@"5slfjhdfjh092834932hjksnfjknskjfnd"];
    [log PutClsContent:@"content_key_6" value:@"6slfjhdfjh092834932hjksnfjknskjfnd"];
    [log PutClsContent:@"content_key_7" value:@"7slfjhdfjh092834932hjksnfjknskjfnd"];
    [log PutClsContent:@"content_key_8" value:@"8slfjhdfjh092834932hjksnfjknskjfnd"];
    [log PutClsContent:@"content_key_9" value:@"9abcdefghijklmnopqrstuvwxyz0123456789"];
    [log PutClsContent:@"content" value:@"中文"];

//    [log SetTime:[[NSDate date] timeIntervalSince1970]*1000];
    return log;
}


@end
