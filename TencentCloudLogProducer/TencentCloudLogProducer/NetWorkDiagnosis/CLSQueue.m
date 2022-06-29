//
//  CLSQueue.m
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import "CLSQueue.h"

@interface CLSQueue ()
+ (instancetype)sharedInstance;
@property (nonatomic) dispatch_queue_t que;
@end

@implementation CLSQueue

+ (instancetype)sharedInstance {
    static CLSQueue *sharedInstance = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });

    return sharedInstance;
}
- (instancetype)init {
    if (self = [super init]) {
        _que = dispatch_queue_create("qnn_que_serial", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

+ (void)async_run_serial:(dispatch_block_t)block {
    dispatch_async([CLSQueue sharedInstance].que, ^{
        block();
    });
}

+ (void)async_run_main:(dispatch_block_t)block {
    dispatch_async(dispatch_get_main_queue(), block);
}
@end
