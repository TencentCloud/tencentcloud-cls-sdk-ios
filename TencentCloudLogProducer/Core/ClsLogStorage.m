#import "ClsLogStorage.h"
#import "FMDB.h"
#import "ClsLogModel.h"

static NSString *const kDBName = @"cls_log_cache.db";
static NSString *const kLogTable = @"cls_log_table";
static NSUInteger kEvictBatchSize = 100;

static const NSInteger  kDeleteMaxRetries = 3;
static const useconds_t kDeleteBackoffUs[kDeleteMaxRetries] = {
    50 * 1000, 150 * 1000, 400 * 1000
};

// 3.3.1 补丁：连续 N 次 DELETE 返回 changes < expected 即判为持续性 DB 异常，
// 走失败重试链路最终触发熔断，避免 workLoop 内层 while(YES) 把单次失败放大成重传风暴。
// 阈值 >= 2 兼容真·evict race（evict 和 workLoop 偶发竞态单发不触发）。
static const NSInteger kShortDeleteFuseThreshold = 3;

@interface ClsLogStorage ()
@property (nonatomic, strong) FMDatabaseQueue *dbQueue;
@property (nonatomic, strong) dispatch_queue_t writeQueue;
@property (nonatomic, assign) uint64_t maxDatabaseSize;
@property (atomic, assign, readwrite) BOOL isDbWritable;
@property (atomic, assign) NSInteger consecutiveShortDeleteCount;
@end

@implementation ClsLogStorage

+ (instancetype)sharedInstance {
    static ClsLogStorage *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ClsLogStorage alloc] init];
        [instance setupDatabase];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *dbPath = [docPath stringByAppendingPathComponent:kDBName];
        _dbQueue = [FMDatabaseQueue databaseQueueWithPath:dbPath];
        _writeQueue = dispatch_queue_create("com.tencent.cls.storage.write", DISPATCH_QUEUE_SERIAL);
        CLSLog(@"database path：%@", dbPath);
        _maxDatabaseSize = 32 * 1024 * 1024;
        _isDbWritable = YES;
    }
    return self;
}

- (void)setMaxDatabaseSize:(uint64_t)maxSize {
    @synchronized (self) {
        if (maxSize > 0) {
            _maxDatabaseSize = maxSize;
            CLSLog(@"database update for：%.2f MB", maxSize / 1024.0 / 1024.0);
        }
    }
}

#pragma mark - 建表（#13 WAL + synchronous=NORMAL + journal_size_limit）
- (void)setupDatabase {
    [_dbQueue inDatabase:^(FMDatabase *db) {
        NSString *mode = [db stringForQuery:@"PRAGMA journal_mode=WAL"];
        if (![mode.lowercaseString isEqualToString:@"wal"]) {
            CLSLog(@"enable WAL failed, current mode: %@", mode);
        }
        [db executeUpdate:@"PRAGMA synchronous=NORMAL"];
        [db stringForQuery:@"PRAGMA journal_size_limit=4194304"];

        NSString *createSQL = [NSString stringWithFormat:
                              @"CREATE TABLE IF NOT EXISTS %@ ("
                              "_id INTEGER PRIMARY KEY AUTOINCREMENT, "
                              "log_item_data TEXT NOT NULL, "
                              "topic_id TEXT NOT NULL, "
                              "create_time INTEGER NOT NULL)",
                              kLogTable];

        NSString *timeIndexSQL = [NSString stringWithFormat:
                                 @"CREATE INDEX IF NOT EXISTS time_idx ON %@ (create_time);",
                                 kLogTable];

        BOOL success = [db executeUpdate:createSQL];
        if (success) {
            success = [db executeUpdate:timeIndexSQL];
        }
        if (success) {
            CLSLog(@"create table success");
        } else {
            CLSLog(@"create table failed: %@", db.lastError);
        }
    }];
}

#pragma mark - #12 按实际使用量判断（去 VACUUM，批量 DELETE 到 90% 水位）
- (uint64_t)usedBytesInDatabase:(FMDatabase *)db {
    uint64_t pageCount = (uint64_t)[db longForQuery:@"PRAGMA page_count"];
    uint64_t freeCount = (uint64_t)[db longForQuery:@"PRAGMA freelist_count"];
    uint64_t pageSize = (uint64_t)[db longForQuery:@"PRAGMA page_size"];
    return (pageCount - freeCount) * pageSize;
}

- (void)evictIfNeededInDatabase:(FMDatabase *)db {
    uint64_t maxSize = self.maxDatabaseSize;
    if ([self usedBytesInDatabase:db] <= maxSize) return;

    uint64_t target = maxSize / 10 * 9;
    NSString *deleteSQL = [NSString stringWithFormat:
        @"DELETE FROM %@ WHERE _id IN (SELECT _id FROM %@ ORDER BY create_time ASC LIMIT %lu)",
        kLogTable, kLogTable, (unsigned long)kEvictBatchSize];
    while ([self usedBytesInDatabase:db] > target) {
        if (![db executeUpdate:deleteSQL] || db.changes == 0) break;
    }
}

#pragma mark - 插入日志（#11 私有串行队列 + #14 写入端校验 + #12 freelist 回收）
- (void)writeLog:(Log *)log
        topicId:(NSString *)topicId
      completion:(nullable void(^)(BOOL success, NSError * _Nullable error))completion {
    if (!log || !topicId.length) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"LogDB" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"topicId or log is empty"}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error); });
        }
        return;
    }

    if (log.time == 0) {
        log.time = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    }

    NSData *logData = [log data];
    if (!logData.length) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"LogDB" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"Protobuf 序列化失败"}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, err); });
        }
        return;
    }

    // #14：写入端提前校验 512KB 上限，超限直接 completion 失败，不入库
    if (logData.length > kCLSMaxSingleLogBytes) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"LogDB" code:-4
                                           userInfo:@{NSLocalizedDescriptionKey:@"log exceeds 512KB"}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, err); });
        }
        return;
    }

    NSString *base64Data = [logData base64EncodedStringWithOptions:0];
    if (!base64Data.length) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"LogDB" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"base64 encode failed"}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, err); });
        }
        return;
    }

    // #11 修复：改为 SDK 私有串行队列，不占用 global queue 共享线程
    dispatch_async(self.writeQueue, ^{
        __block BOOL success = NO;
        __block NSError *dbError = nil;

        [self.dbQueue inDatabase:^(FMDatabase *db) {
            // #12 修复：按 freelist 判定、批量 DELETE 到 90% 水位，不再 VACUUM
            [self evictIfNeededInDatabase:db];

            NSTimeInterval currentTimeSec = [[NSDate date] timeIntervalSince1970];
            int64_t currentTimeMs = (int64_t)(currentTimeSec * 1000);

            NSString *insertSQL = [NSString stringWithFormat:
                                  @"INSERT INTO %@ (log_item_data, topic_id, create_time) "
                                  "VALUES (?, ?, ?)", kLogTable];

            success = [db executeUpdate:insertSQL, base64Data, topicId, @(currentTimeMs)];
            if (!success) {
                dbError = db.lastError;
                CLSLog(@"insert failed: %@", dbError);
            }
        }];

        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(success, dbError); });
        }
    });
}

#pragma mark - 查询待发送日志（#15 坏行删除）
- (NSArray<NSDictionary *> *)queryPendingLogs:(NSUInteger)limit {
    if (!self.isDbWritable) {
        CLSLog(@"queryPendingLogs skipped: DB tripped");
        return @[];
    }
    __block NSMutableArray *result = [NSMutableArray array];

    [_dbQueue inDatabase:^(FMDatabase *db) {
        NSString *querySQL = [NSString stringWithFormat:
                             @"SELECT _id, log_item_data, topic_id "
                             "FROM %@ "
                             "ORDER BY create_time ASC LIMIT %lu",
                             kLogTable, (unsigned long)limit];

        FMResultSet *rs = [db executeQuery:querySQL];
        if (!rs) {
            CLSLog(@"select failed: %@", db.lastError);
            return;
        }

        // #15 修复：收集坏行 _id，在同一个 inDatabase 中删除
        NSMutableArray<NSNumber *> *badIds = [NSMutableArray array];
        while ([rs next]) {
            NSNumber *logId = @([rs longLongIntForColumn:@"_id"]);
            NSString *base64Data = [rs stringForColumn:@"log_item_data"];
            NSString *topicId = [rs stringForColumn:@"topic_id"];

            if (base64Data.length == 0 || topicId.length == 0) {
                [badIds addObject:logId];
                continue;
            }
            NSData *itemData = [[NSData alloc] initWithBase64EncodedString:base64Data options:0];
            Log *log = itemData ? [Log parseFromData:itemData error:nil] : nil;
            if (!log) {
                [badIds addObject:logId];
                continue;
            }
            [result addObject:@{
                @"id": logId,
                @"log_item": log,
                @"topic_id": topicId
            }];
        }
        [rs close];

        if (badIds.count > 0) {
            NSString *idsStr = [badIds componentsJoinedByString:@","];
            NSString *delSQL = [NSString stringWithFormat:
                                @"DELETE FROM %@ WHERE _id IN (%@)", kLogTable, idsStr];
            if (![db executeUpdate:delSQL]) {
                // 坏行删除失败不触发 isDbWritable 熔断
                CLSLog(@"delete bad rows failed: %@", db.lastError);
            }
        }
    }];

    return result;
}

#pragma mark - 删除已发送日志
- (BOOL)deleteSentLogsWithIds:(NSArray<NSNumber *> *)logIds {
    if (logIds.count == 0) return YES;
    if (!self.isDbWritable) {
        CLSLog(@"deleteSentLogsWithIds skipped: DB tripped");
        return NO;
    }

    for (NSInteger attempt = 0; attempt <= kDeleteMaxRetries; attempt++) {
        __block BOOL ok = NO;
        __block int lastCode = 0;
        __block NSString *lastMsg = nil;

        [_dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
            NSString *idsStr = [logIds componentsJoinedByString:@","];
            NSString *sql = [NSString stringWithFormat:
                            @"DELETE FROM %@ WHERE _id IN (%@)", kLogTable, idsStr];

            if (![db executeUpdate:sql]) {
                lastCode = db.lastErrorCode;
                lastMsg = db.lastErrorMessage;
                *rollback = YES;
                return;
            }
            if ((NSUInteger)db.changes < logIds.count) {
                // 3.3.1 补丁：changes < expected 不再无条件容忍
                // 偶发 1~2 次：兼容真·evict race（writeLog 触发的容量淘汰可能先删了部分 _id）
                // 连续 >= 阈值：判为持续性 DB 异常（READONLY/journal 失败/多实例可见性等），走熔断
                NSInteger n = (self.consecutiveShortDeleteCount += 1);
                CLSLog(@"delete affected=%d expected=%lu short#%ld (threshold=%ld)",
                       db.changes, (unsigned long)logIds.count,
                       (long)n, (long)kShortDeleteFuseThreshold);
                if (n >= kShortDeleteFuseThreshold) {
                    lastCode = -1;
                    lastMsg = @"persistent short delete";
                    *rollback = YES;
                    return;  // ok 保持 NO → 走 attempt retry → 耗尽后熔断
                }
                // 阈值内：仍视为成功（兼容真·evict race）
            } else {
                self.consecutiveShortDeleteCount = 0;  // 任意一次完全命中即复位
            }
            ok = YES;
        }];

        if (ok) {
            if (attempt > 0) {
                CLSLog(@"delete succeeded after %ld retries", (long)attempt);
            }
            return YES;
        }

        CLSLog(@"delete attempt %ld failed: code=%d msg=%@",
               (long)attempt, lastCode, lastMsg ?: @"");

        if (attempt < kDeleteMaxRetries) {
            usleep(kDeleteBackoffUs[attempt]);
        }
    }

    CLSLog(@"delete failed permanently after %ld retries, tripping switch",
           (long)kDeleteMaxRetries);
    self.isDbWritable = NO;
    return NO;
}

@end
