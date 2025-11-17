#import "CLSNetworkTool.h"
#import <CommonCrypto/CommonHMAC.h>
#import "cls_lz4.h"
#import "Reachability.h"
#import "CLSSignatureTool.h"

@implementation ClsPostOption
- (instancetype)init {
    if (self = [super init]) {
        _compressType = 1; // 默认使用LZ4压缩
        _socketTimeout = 60;
        _connectTimeout = 60;
    }
    return self;
}
@end

@implementation CLSSendResult
@end

@implementation CLSNetworkTool

#pragma mark - 核心修改：使用cls_lz4库进行压缩
+ (NSData *)lz4CompressData:(NSData *)data {
    if (!data || data.length == 0) {
        return nil;
    }
    
    // 获取原始数据大小（对应C++的originalSize）
    int originalSize = (int)data.length;
    // 计算压缩缓冲区最大所需大小（对应C++的LZ4_compressBound）
    int maxCompressedSize = LZ4_compressBound(originalSize);
    if (maxCompressedSize <= 0) {
        CLSLog(@"[ERROR] LZ4_compressBound failed");
        return nil;
    }
    
    // 分配压缩缓冲区（对应C++的std::vector<char> compressedData）
    void *compressedBuffer = malloc(maxCompressedSize);
    if (!compressedBuffer) {
        CLSLog(@"[ERROR] malloc compressed buffer failed");
        return nil;
    }
    
    // 执行LZ4压缩（对应C++的LZ4_compress_default）
    int actualCompressedSize = LZ4_compress_default(
        data.bytes,          // 原始数据指针
        compressedBuffer,    // 压缩缓冲区指针
        originalSize,        // 原始数据大小
        maxCompressedSize    // 压缩缓冲区最大大小
    );
    
    if (actualCompressedSize <= 0) {
        CLSLog(@"[ERROR] LZ4_compress_default failed, error code: %d", actualCompressedSize);
        free(compressedBuffer);
        return nil;
    }
    
    // 将压缩后的数据转为NSData（对应C++的std::string(compressedData.data(), compressedSizeActual)）
    NSData *compressedData = [NSData dataWithBytes:compressedBuffer length:actualCompressedSize];
    free(compressedBuffer); // 释放缓冲区
    
    return compressedData;
}

+ (CLSSendResult *)sendPostRequestSyncWithUrl:(NSString *)url
                                     headers:(NSDictionary *)headers
                                       body:(NSData *)body
                                     option:(ClsPostOption *)option {
    // 防御性校验：参数合法性检查
    if (!option) {
        CLSSendResult *result = [[CLSSendResult alloc] init];
        result.statusCode = -104;
        result.message = @"请求配置参数为空";
        return result;
    }
    if (body.length == 0) {
        CLSSendResult *result = [[CLSSendResult alloc] init];
        result.statusCode = -105;
        result.message = @"请求体为空";
        return result;
    }
    
    // 1. 校验URL（增强判断，避免无效URL）
    NSURL *requestUrl = [NSURL URLWithString:url];
    if (!requestUrl || !requestUrl.host || !requestUrl.scheme) {
        CLSSendResult *result = [[CLSSendResult alloc] init];
        result.statusCode = -100;
        result.message = [NSString stringWithFormat:@"无效的URL: %@", url];
        return result;
    }
    
    // 2. 构建请求（统一超时设置，避免冲突）
    NSTimeInterval socketTimeout = option.socketTimeout > 0 ? option.socketTimeout : 60; // 默认60秒
    NSTimeInterval connectTimeout = option.connectTimeout > 0 ? option.connectTimeout : 60; // 默认60秒
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestUrl
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:socketTimeout]; // 与传输超时保持一致
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    // 补充Content-Length头（部分服务器需要）
    [request setValue:@(body.length).stringValue forHTTPHeaderField:@"Content-Length"];
    // 设置请求头（过滤空值，避免非法头字段）
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        if (key.length > 0 && value.length > 0) {
            [request setValue:value forHTTPHeaderField:key];
        }
    }];
    
    // 3. 配置会话（使用单例会话，减少资源消耗）
    static NSURLSession *sharedSession = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest = socketTimeout; // 传输超时（无数据传输时的等待时间）
        config.timeoutIntervalForResource = connectTimeout; // 连接超时（建立连接的最长时间）
        sharedSession = [NSURLSession sessionWithConfiguration:config];
    });
    
    // 4. 信号量同步机制（增强安全性）
    __block NSHTTPURLResponse *response = nil;
    __block NSError *error = nil;
    __block NSData *responseData = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    if (!semaphore) { // 极端情况：信号量创建失败
        CLSSendResult *result = [[CLSSendResult alloc] init];
        result.statusCode = -102;
        result.message = @"信号量创建失败（内存不足）";
        return result;
    }
    
    // 发起请求任务
    NSURLSessionDataTask *task = [sharedSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable resp, NSError * _Nullable err) {
        @synchronized (semaphore) { // 避免多线程竞态
            responseData = data;
            response = (NSHTTPURLResponse *)resp;
            error = err;
            dispatch_semaphore_signal(semaphore); // 任务完成，唤醒等待
        }
    }];
    [task resume];
    
    // 5. 等待超时控制（取最大超时，确保覆盖所有场景）
    NSTimeInterval maxTimeout = MAX(socketTimeout, connectTimeout);
    dispatch_time_t timeoutTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(maxTimeout * NSEC_PER_SEC));
    // 检查当前线程状态，避免在已取消的线程上等待
    if ([NSThread currentThread].isCancelled) {
        [task cancel];
        dispatch_semaphore_signal(semaphore); // 释放信号量，避免泄漏
        CLSSendResult *result = [[CLSSendResult alloc] init];
        result.statusCode = -103;
        result.message = @"当前线程已取消，请求终止";
        return result;
    }
    // 执行等待（核心同步逻辑）
    int semaphoreResult = dispatch_semaphore_wait(semaphore, timeoutTime);
    
    // 6. 结果处理（细分错误类型，增强可调试性）
    CLSSendResult *result = [[CLSSendResult alloc] init];
    @synchronized (semaphore) { // 与回调中的同步块匹配，确保数据一致性
        if (semaphoreResult != 0) {
            // 信号量超时：未在规定时间内收到回调
            result.statusCode = -101;
            result.message = [NSString stringWithFormat:@"请求超时（最大等待 %.1fs）", maxTimeout];
            [task cancel]; // 超时后取消任务，释放资源
        } else if (error) {
            // 系统层面错误（包括连接失败、传输错误等）
            result.statusCode = error.code;
            result.message = error.localizedDescription;
            // 细分超时类型
            if (error.code == NSURLErrorTimedOut) {
                result.message = [NSString stringWithFormat:@"请求超时（连接: %.1fs / 传输: %.1fs）", connectTimeout, socketTimeout];
            } else if (error.code == NSURLErrorCancelled) {
                result.message = @"请求被取消";
            } else if (error.code == NSURLErrorCannotConnectToHost) {
                result.message = @"无法连接到服务器";
            }
        } else if (!response) {
            // 无响应（极端情况，如网络中断）
            result.statusCode = -106;
            result.message = @"未收到服务器响应";
        } else {
            // 正常响应
            result.statusCode = response.statusCode;
            result.requestID = response.allHeaderFields[@"x-cls-requestid"] ?: @"";
            // 解析响应体（支持UTF-8和GBK等编码，避免乱码）
            if (responseData.length > 0) {
                NSString *responseStr = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
                if (!responseStr) {
                    // 尝试其他编码（如GBK）
                    NSStringEncoding gbkEncoding = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
                    responseStr = [[NSString alloc] initWithData:responseData encoding:gbkEncoding] ?: @"";
                }
                result.message = responseStr;
            }
        }
    }
    
    return result;
}


+ (NSString *)generateSignatureWithSecretId:(NSString *)secretId
                                secretKey:(NSString *)secretKey
                                   method:(NSString *)method
                                     path:(NSString *)path
                                    params:(NSDictionary<NSString *, NSString *> *)params
                                   headers:(NSDictionary<NSString *, NSString *> *)headers
                                    expire:(long)expire {
    // 1. 初始化缓冲区（对应C语言的char数组）
    NSMutableString *httpRequestInfo = [NSMutableString string];
    NSMutableString *uriParmList = [NSMutableString string];
    NSMutableString *headerList = [NSMutableString string];
    NSMutableString *strToSign = [NSMutableString string];
    
    // 2. 处理method（转为小写，对应C的strlowr）
    NSString *lowerMethod = [CLSSignatureTool stringToLower:method];
    [httpRequestInfo appendFormat:@"%@\n", lowerMethod];
    
    // 3. 拼接path（对应C的strcat(http_request_info, path)）
    [httpRequestInfo appendFormat:@"%@\n", path];
    
    // 4. 处理params（遍历、编码、拼接，对应C的params遍历）
    // 先对params的key排序（C的map_first按key顺序遍历）
    NSArray *sortedParamKeys = [[params allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSInteger i = 0; i < sortedParamKeys.count; i++) {
        NSString *key = sortedParamKeys[i];
        NSString *value = params[key] ?: @"";
        
        // 拼接uri_parm_list（key;key...）
        if (i > 0) {
            [uriParmList appendString:@";"];
        }
        [uriParmList appendString:key];
        
        // 拼接http_request_info（key=编码后的值&...）
        [httpRequestInfo appendString:key];
        [httpRequestInfo appendString:@"="];
        NSString *encodedValue = [CLSSignatureTool urlEncode:value]; // 对应C的urlencode
        [httpRequestInfo appendString:encodedValue];
        
        // 非最后一个参数加&
        if (i != sortedParamKeys.count - 1) {
            [httpRequestInfo appendString:@"&"];
        }
    }
    
    // 5. 拼接params后的换行（对应C的strcat(http_request_info, "\n")）
    [httpRequestInfo appendString:@"\n"];
    
    // 6. 处理headers（筛选、小写key、编码、拼接，对应C的headers遍历）
    NSArray *sortedHeaderKeys = [[headers allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *originalKey in sortedHeaderKeys) {
        // 转为小写key（对应C的strlowr(node->key, sign_key)）
        NSString *key = [CLSSignatureTool stringToLower:originalKey];
        
        // 筛选需要签名的头部（对应C的if条件）
        if (!([key isEqualToString:@"content-type"] ||
             [key isEqualToString:@"content-md5"] ||
             [key isEqualToString:@"host"] ||
             [key hasPrefix:@"x-"])) {
            continue;
        }
        
        NSString *value = headers[originalKey] ?: @"";
        
        // 拼接header_list（key;key...）
        if (headerList.length > 0) {
            [headerList appendString:@";"];
        }
        [headerList appendString:key];
        
        // 拼接http_request_info（key=编码后的值&...）
        [httpRequestInfo appendString:key];
        [httpRequestInfo appendString:@"="];
        NSString *encodedValue = [CLSSignatureTool urlEncode:value]; // 对应C的urlencode
        [httpRequestInfo appendString:encodedValue];
        [httpRequestInfo appendString:@"&"]; // 先加&，最后处理
    }
    // 7. 修正header_list和http_request_info的末尾字符（对应C的截断逻辑）
    if (httpRequestInfo.length > 0) {
        [httpRequestInfo deleteCharactersInRange:NSMakeRange(httpRequestInfo.length - 1, 1)];
        [httpRequestInfo appendString:@"\n"];
    }
    
    // 8. 生成signed_time（对应C的snprintf(signed_time, ...)）
    time_t now = time(NULL);
    time_t startTime = now - 60;
    time_t endTime = now + expire;
    NSString *signedTime = [NSString stringWithFormat:@"%lu;%lu", (unsigned long)startTime, (unsigned long)endTime];
    // 9. 计算signkey（对应C的_hmac_sha1(secret_key, signed_time, ...)）
    NSData *signedTimeData = [signedTime dataUsingEncoding:NSUTF8StringEncoding];
    NSString *signKey = [CLSSignatureTool hmacSha1WithKey:secretKey data:signedTimeData];
    
    // 10. 计算http_request_info的SHA1（对应C的_sha1(http_request_info, ...)）
    NSData *httpInfoData = [httpRequestInfo dataUsingEncoding:NSUTF8StringEncoding];
    NSString *httpInfoSha1 = [CLSSignatureTool sha1:httpInfoData];
    // 11. 构建str_to_sign（对应C的strcat(str_to_sign, ...)）
    [strToSign appendString:@"sha1\n"];
    [strToSign appendFormat:@"%@\n", signedTime];
    [strToSign appendFormat:@"%@\n", httpInfoSha1];
    
    // 12. 计算最终签名（对应C的_hmac_sha1(signkey, str_to_sign, ...)）
    NSData *strToSignData = [strToSign dataUsingEncoding:NSUTF8StringEncoding];
    NSString *signature = [CLSSignatureTool hmacSha1WithKey:signKey data:strToSignData];
    // 13. 拼接最终签名串（对应C的snprintf(c_signature, ...)）
    return [NSString stringWithFormat:
            @"q-sign-algorithm=sha1&q-ak=%@&q-sign-time=%@&q-key-time=%@&q-header-list=%@&q-url-param-list=%@&q-signature=%@",
            secretId,
            signedTime,
            signedTime,
            headerList,
            uriParmList,
            signature];
}

+ (uint64_t)sizeOfLogItem:(Log *)log {
    return log.data.length;
}

+ (BOOL)isNetworkAvailable {
    Reachability *reachability = [Reachability reachabilityForInternetConnection];
    // 获取当前网络状态
    NetworkStatus status = [reachability currentReachabilityStatus];
    // 状态为 NotReachable 表示无网络
    return (status != NotReachable);
}


@end
