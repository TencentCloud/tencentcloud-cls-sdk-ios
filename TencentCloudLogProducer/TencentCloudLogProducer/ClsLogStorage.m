#import "ClsLogStorage.h"
#import "FMDB.h"
#import "ClsLogModel.h"

static NSString *const kDBName = @"cls_log_cache.db";
static NSString *const kLogTable = @"cls_log_table";
static NSUInteger kEvictBatchSize = 100;

@interface ClsLogStorage ()
@property (nonatomic, strong) FMDatabaseQueue *dbQueue;
@property (nonatomic, assign) uint64_t maxDatabaseSize;
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
        CLSLog(@"database path：%@", dbPath);
        _maxDatabaseSize = 32 * 1024 * 1024; // 默认32MB，与Android一致
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

#pragma mark - 建表（无修改）
- (void)setupDatabase {
    [_dbQueue inDatabase:^(FMDatabase *db) {
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
            CLSLog(@"create table success fields：_id, log_item_data, topic_id, create_time");
        } else {
            CLSLog(@"create table failed: %@", db.lastError);
        }
    }];
}

#pragma mark - 插入日志（核心修改：插入前先清理）
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
    
    // Protobuf序列化（无修改）
    NSData *logData = [log data];
    if (!logData.length) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"LogDB" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"Protobuf 序列化失败"}];
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
    
    // 异步写入（核心修改：插入前先执行清理）
    // 异步写入（核心优化：将清理、压缩、插入合并为单个数据库任务）
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        __block BOOL success = NO;
        __block NSError *dbError = nil;
        
        // 将清理、VACUUM、插入合并到同一个数据库任务中
        [self.dbQueue inDatabase:^(FMDatabase *db) {
            // 1. 清理旧数据（包含DELETE + VACUUM）
            BOOL hasCleanedData = NO;
            while (YES) {
                uint64_t currentSize = [self getDatabaseSize];
                if (currentSize <= self.maxDatabaseSize) {
                    CLSLog(@"当前数据库大小：%.2f MB（未超阈值），无需清理", currentSize / 1024.0 / 1024.0);
                    break;
                }
                
                // 1.1 批量删除最早的日志
                NSUInteger deletedCount = 0;
                NSString *deleteSQL = [NSString stringWithFormat:
                                      @"DELETE FROM %@ "
                                      "ORDER BY create_time ASC "
                                      "LIMIT %lu",
                                      kLogTable, (unsigned long)kEvictBatchSize];
                
                BOOL deleteSuccess = [db executeUpdate:deleteSQL];
                if (deleteSuccess) {
                    deletedCount = db.changes;
                    CLSLog(@"清理旧数据成功，删除条数：%lu，清理前大小：%.2f MB",
                          (unsigned long)deletedCount,
                          currentSize / 1024.0 / 1024.0);
                } else {
                    CLSLog(@"清理旧数据失败：%@", db.lastError);
                    dbError = db.lastError;
                    break; // 清理失败，终止后续操作
                }
                
                // 1.2 执行VACUUM（删除后立即压缩）
                if (deletedCount > 0) {
                    hasCleanedData = YES;
                    if ([db executeUpdate:@"VACUUM"]) {
                        uint64_t newSize = [self getDatabaseSize];
                        CLSLog(@"VACUUM 完成，压缩后大小：%.2f MB", newSize / 1024.0 / 1024.0);
                    } else {
                        CLSLog(@"VACUUM 失败：%@", db.lastError);
                        // VACUUM失败不终止，仅记录日志
                    }
                } else {
                    CLSLog(@"无更多数据可清理，当前大小：%.2f MB", currentSize / 1024.0 / 1024.0);
                    break;
                }
            }
            
            // 2. 执行插入操作（清理完成后才插入）
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
        
        // 3. 回调结果
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(success, dbError); });
        }
    });
}

#pragma mark - 数据库大小计算（无修改，与Android一致）
- (uint64_t)getDatabaseSize {
    NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dbPath = [docPath stringByAppendingPathComponent:kDBName];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:dbPath]) {
        CLSLog(@"数据库文件不存在：%@", dbPath);
        return 0;
    }
    
    NSError *error = nil;
    NSDictionary<NSFileAttributeKey, id> *fileAttrs = [fileManager attributesOfItemAtPath:dbPath error:&error];
    if (error) {
        CLSLog(@"获取数据库大小失败：%@", error.localizedDescription);
        return 0;
    }
    
    return [fileAttrs[NSFileSize] unsignedLongLongValue];
}

#pragma mark - 查询待发送日志（无修改）
- (NSArray<NSDictionary *> *)queryPendingLogs:(NSUInteger)limit {
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
        
        while ([rs next]) {
            NSNumber *logId = @([rs intForColumn:@"_id"]);
            NSString *base64Data = [rs stringForColumn:@"log_item_data"];
            NSString *topicId = [rs stringForColumn:@"topic_id"];
            
            if (logId && base64Data.length && topicId.length) {
                NSData *itemData = [[NSData alloc] initWithBase64EncodedString:base64Data options:0];
                if (!itemData) {
                    CLSLog(@"log id %@ decode failed", logId);
                    continue;
                }
                NSError *error = nil;
                Log *log = [Log parseFromData:itemData error:&error];
                if (log) {
                    [result addObject:@{
                        @"id": logId,
                        @"log_item": log,
                        @"topic_id": topicId
                    }];
                    CLSLog(@"log id %@（topic: %@）read success", logId, topicId);
                } else {
                    CLSLog(@"log id %@ read failed", logId);
                }
            }
        }
        [rs close];
    }];
    
    return result;
}

#pragma mark - 删除已发送日志（无修改）
- (void)deleteSentLogsWithIds:(NSArray<NSNumber *> *)logIds {
    if (logIds.count == 0) return;
    
    [_dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        NSString *idsStr = [logIds componentsJoinedByString:@","];
        NSString *sql = [NSString stringWithFormat:
                        @"DELETE FROM %@ WHERE _id IN (%@)",
                        kLogTable, idsStr];
        
        if (![db executeUpdate:sql]) {
            CLSLog(@"delete log failed: %@", db.lastError);
            *rollback = YES;
        }
    }];
}

@end
