// ClsLogStorage.h（接口不变，内部实现调整）
#import <Foundation/Foundation.h>
#import "ClsLogModel.h"
#import "ClsLogs.pbobjc.h"

@interface ClsLogStorage : NSObject

+ (instancetype)sharedInstance;

- (void)setMaxDatabaseSize:(uint64_t)maxSize;

- (void)writeLog:(Log *)logItem
        topicId:(NSString *)topicId
      completion:(nullable void(^)(BOOL success, NSError * _Nullable error))completion;

- (NSArray<NSDictionary *> *)queryPendingLogs:(NSUInteger)limit;

- (void)deleteSentLogsWithIds:(NSArray<NSNumber *> *)logIds;

@end

