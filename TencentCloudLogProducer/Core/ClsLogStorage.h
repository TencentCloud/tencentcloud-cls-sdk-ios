// ClsLogStorage.h
#import <Foundation/Foundation.h>
#import "ClsLogModel.h"
#import "ClsLogs.pbobjc.h"

NS_ASSUME_NONNULL_BEGIN

@interface ClsLogStorage : NSObject

+ (instancetype)sharedInstance;

- (void)setMaxDatabaseSize:(uint64_t)maxSize;

- (void)writeLog:(Log *)logItem
        topicId:(NSString *)topicId
      completion:(nullable void(^)(BOOL success, NSError * _Nullable error))completion;

- (NSArray<NSDictionary *> *)queryPendingLogs:(NSUInteger)limit;

- (BOOL)deleteSentLogsWithIds:(NSArray<NSNumber *> *)logIds;

@property (atomic, assign, readonly) BOOL isDbWritable;

@end

NS_ASSUME_NONNULL_END
