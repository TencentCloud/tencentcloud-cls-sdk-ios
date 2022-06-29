//
//  CLSQueue.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CLSQueue : NSObject
+ (void)async_run_serial:(dispatch_block_t)block;

+ (void)async_run_main:(dispatch_block_t)block;
@end

NS_ASSUME_NONNULL_END
