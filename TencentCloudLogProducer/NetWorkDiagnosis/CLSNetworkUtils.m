//
//  CLSNetworkUtils.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/13.
//

// CLSNetworkUtils.m
#import "CLSNetworkUtils.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <sys/utsname.h>
#import <UIKit/UIKit.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#include <net/if.h>
#include <netdb.h>
#include <sys/socket.h>
#include <errno.h>
#include <AssertMacros.h>
#import "CLSDeviceUtils.h"
#if CLS_HAS_CORE_TELEPHONY
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#endif
#import <resolv.h> // 用于获取DNS配置

@implementation CLSNetworkUtils

+ (NSDictionary *)parseNetToken:(NSString *)netToken {
    // 1. 入参校验
    if (netToken.length == 0) {
        NSLog(@"[CLS] 入参异常：netToken=%@", netToken);
        return @{};
    }
    
    // 2. 修复Base64解码容错（补充填充符）
    NSString *base64String = [netToken stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    base64String = [base64String stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    
    // 补全Base64填充符（URL安全Base64可能缺失=）
    NSUInteger padding = base64String.length % 4;
    if (padding > 0) {
        base64String = [base64String stringByAppendingString:[NSString stringWithFormat:@"%@", [@"" stringByPaddingToLength:4 - padding withString:@"=" startingAtIndex:0]]];
    }
    
    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:base64String options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (!decodedData) {
        NSLog(@"[CLS] token Base64解码失败，原始token：%@", netToken);
        return @{};
    }

    // 3. 解析JSON并容错
    NSError *jsonError = nil;
    NSDictionary *tokenDict = [NSJSONSerialization JSONObjectWithData:decodedData options:0 error:&jsonError];
    if (jsonError || !tokenDict) {
        NSLog(@"[CLS] token JSON解析失败：%@，解码后字符串：%@", jsonError.localizedDescription, [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding]);
        return @{};
    }

    // 4. 提取字段并容错
    NSString *networkAppId = tokenDict[@"n_a_id"] ?: @"";
    NSString *appKey = tokenDict[@"key"] ?: @"";
    NSString *uin = tokenDict[@"uin"] ? [NSString stringWithFormat:@"%@", tokenDict[@"uin"]] : @"";
    NSString *region = tokenDict[@"region"] ?: @"";
    NSString *topicId = tokenDict[@"topic_id"] ?: @"";
    
    if (networkAppId.length == 0 || appKey.length == 0 || uin.length == 0 || region.length == 0 || topicId.length == 0) {
        NSLog(@"[CLS] token解析缺少必要字段：n_a_id=%@, key=%@, uin=%@", networkAppId, appKey, uin);
        return @{};
    }

    // 5. 返回解析后的核心字段
    return @{
        @"networkAppId": networkAppId,
        @"appKey": appKey,
        @"uin": uin,
        @"region":region,
        @"topic_id":topicId
    };
}

+ (NSDictionary *)getNetworkEnvironmentInfo:(NSString *)usedNet networkAppId:(NSString *)networkAppId appKey:(NSString *)appKey uin:(NSString *)uin endpoint:(NSString *)endpoint interfaceName:(NSString *)interfaceName{
    // 调用独立封装的Token解析方法
    if(networkAppId == nil || networkAppId.length == 0 || appKey == nil || appKey.length == 0 || uin == nil || uin.length == 0 || endpoint == nil || endpoint.length == 0){
        return @{};
    }

    // C Socket 实现只支持 HTTP，强制使用 HTTP 协议
    if (![endpoint.lowercaseString hasPrefix:@"http"]) {
        endpoint = [NSString stringWithFormat:@"http://%@", endpoint];
        NSLog(@"[CLS] 自动补充HTTP协议头（C Socket 实现），修正后endpoint：%@", endpoint);
    } else if ([endpoint.lowercaseString hasPrefix:@"https://"]) {
        // 将 HTTPS 替换为 HTTP
        endpoint = [endpoint stringByReplacingOccurrencesOfString:@"https://" withString:@"http://" options:NSCaseInsensitiveSearch range:NSMakeRange(0, 8)];
        NSLog(@"[CLS] ⚠️ C Socket 不支持 HTTPS，已自动转换为 HTTP：%@", endpoint);
    }
    
    // 步骤2：编码URL参数（避免特殊字符导致URL非法）
    NSString *encodedNetworkAppId = [networkAppId stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSString *encodedAppKey = [appKey stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSString *encodedUin = [uin stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    
    // 步骤3：拼接URI（使用编码后的参数）
    NSString *uri = [NSString stringWithFormat:@"/geo?networkappid=%@&appkey=%@&uin=%@",
                     encodedNetworkAppId, encodedAppKey, encodedUin];
    
    // 步骤4：拼接完整URL并校验合法性
    NSString *urlStr = [endpoint stringByAppendingString:uri];
    NSURL *url = [NSURL URLWithString:[urlStr stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]];
    if (!url) {
        NSLog(@"[CLS] URL格式非法，无法初始化NSURL：%@", urlStr);
        return @{};
    }
    
    // 输出完整URL（无截断）
    NSLog(@"[CLS] 最终请求信息：endpoint=%@｜url=%@｜networkAppId=%@｜appKey=%@｜uin=%@", endpoint, url.absoluteString, networkAppId, appKey, uin);

    // ========== 4. 使用 C Socket 发起 HTTP 请求（支持网卡绑定） ==========
    return [self sendHTTPRequestWithSocket:url interfaceName:interfaceName usedNet:usedNet];
}

#pragma mark - C Socket HTTP 请求实现（支持网卡绑定）

+ (NSDictionary *)sendHTTPRequestWithSocket:(NSURL *)url
                              interfaceName:(NSString *)interfaceName
                                    usedNet:(NSString *)usedNet {
    NSLog(@"[CLS Socket] 开始发起 HTTP 请求（网卡：%@）", interfaceName ?: @"默认");
    
    // 1. 解析 URL
    NSString *host = url.host;
    NSString *path = url.path.length > 0 ? url.path : @"/";
    NSString *query = url.query.length > 0 ? [NSString stringWithFormat:@"?%@", url.query] : @"";
    uint16_t port = url.port ? [url.port unsignedShortValue] : 80;  // 默认 HTTP 端口
    
    NSLog(@"[CLS Socket] 请求地址：%@:%d%@%@", host, port, path, query);
    
    // 2. DNS 解析
    struct hostent *hostInfo = gethostbyname([host UTF8String]);
    if (!hostInfo || hostInfo->h_addr_list[0] == NULL) {
        NSLog(@"[CLS Socket] ❌ DNS 解析失败：%@", host);
        return @{};
    }
    
    struct in_addr targetAddr;
    memcpy(&targetAddr, hostInfo->h_addr_list[0], sizeof(struct in_addr));
    NSString *targetIP = [NSString stringWithUTF8String:inet_ntoa(targetAddr)];
    NSLog(@"[CLS Socket] ✅ DNS 解析：%@ -> %@", host, targetIP);
    
    // 3. 创建 socket
    int sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock < 0) {
        NSLog(@"[CLS Socket] ❌ 创建 socket 失败：%s", strerror(errno));
        return @{};
    }
    NSLog(@"[CLS Socket] ✅ Socket 创建成功：fd=%d", sock);
    
    // 4. 绑定网卡（如果指定）
    if (interfaceName && interfaceName.length > 0) {
        unsigned int interfaceIndex = if_nametoindex([interfaceName UTF8String]);
        if (interfaceIndex == 0) {
            NSLog(@"[CLS Socket] ❌ 无效的网卡名称：%@", interfaceName);
            close(sock);
            return @{};
        }
        
        if (setsockopt(sock, IPPROTO_IP, IP_BOUND_IF, &interfaceIndex, sizeof(interfaceIndex)) < 0) {
            NSLog(@"[CLS Socket] ❌ 网卡绑定失败：%s", strerror(errno));
            close(sock);
            return @{};
        }
        NSLog(@"[CLS Socket] ✅ 网卡绑定成功：%@（索引：%u）", interfaceName, interfaceIndex);
    } else {
        NSLog(@"[CLS Socket] 使用系统默认网卡");
    }
    
    // 5. 设置超时（60秒）
    struct timeval timeout;
    timeout.tv_sec = 60;
    timeout.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    
    // 6. 连接服务器
    struct sockaddr_in serverAddr;
    memset(&serverAddr, 0, sizeof(serverAddr));
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_port = htons(port);
    serverAddr.sin_addr = targetAddr;
    
    NSLog(@"[CLS Socket] 连接到 %@:%d ...", targetIP, port);
    if (connect(sock, (struct sockaddr *)&serverAddr, sizeof(serverAddr)) < 0) {
        NSLog(@"[CLS Socket] ❌ 连接失败：%s", strerror(errno));
        close(sock);
        return @{};
    }
    NSLog(@"[CLS Socket] ✅ 连接成功");
    
    // 7. 构建并发送 HTTP 请求
    NSString *httpRequest = [NSString stringWithFormat:
        @"GET %@%@ HTTP/1.1\r\n"
        @"Host: %@\r\n"
        @"User-Agent: TencentCloudLog/1.0\r\n"
        @"Accept: */*\r\n"
        @"Cache-Control: no-cache\r\n"
        @"Connection: close\r\n"
        @"\r\n", path, query, host];
    
    const char *requestData = [httpRequest UTF8String];
    ssize_t sent = send(sock, requestData, strlen(requestData), 0);
    if (sent < 0) {
        NSLog(@"[CLS Socket] ❌ 发送请求失败：%s", strerror(errno));
        close(sock);
        return @{};
    }
    NSLog(@"[CLS Socket] ✅ 已发送 %ld 字节请求", (long)sent);
    
    // 8. 接收响应
    char buffer[8192];
    NSMutableData *responseData = [NSMutableData data];
    ssize_t received;
    
    while ((received = recv(sock, buffer, sizeof(buffer) - 1, 0)) > 0) {
        [responseData appendBytes:buffer length:received];
    }
    close(sock);
    
    if (responseData.length == 0) {
        NSLog(@"[CLS Socket] ❌ 未收到响应数据");
        return @{};
    }
    NSLog(@"[CLS Socket] ✅ 接收到 %lu 字节响应", (unsigned long)responseData.length);
    
    // 9. 解析 HTTP 响应
    NSString *response = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    
    // 提取状态码
    NSRange statusLineRange = [response rangeOfString:@"\r\n"];
    if (statusLineRange.location == NSNotFound) {
        NSLog(@"[CLS Socket] ❌ 无法解析 HTTP 状态行");
        return @{};
    }
    
    NSString *statusLine = [response substringToIndex:statusLineRange.location];
    NSArray *statusParts = [statusLine componentsSeparatedByString:@" "];
    NSInteger statusCode = statusParts.count >= 2 ? [statusParts[1] integerValue] : 0;
    NSLog(@"[CLS Socket] HTTP 状态码：%ld", (long)statusCode);
    
    if (statusCode != 200) {
        NSLog(@"[CLS Socket] ❌ HTTP 状态码异常：%ld", (long)statusCode);
        return @{};
    }
    
    // 提取 JSON 响应体
    NSRange bodyRange = [response rangeOfString:@"\r\n\r\n"];
    if (bodyRange.location == NSNotFound) {
        NSLog(@"[CLS Socket] ❌ 无法解析 HTTP 响应体");
        return @{};
    }
    
    NSString *jsonBody = [response substringFromIndex:bodyRange.location + bodyRange.length];
    NSLog(@"[CLS Socket] 响应体：%@", jsonBody);
    
    // 10. 解析 JSON
    NSData *jsonData = [jsonBody dataUsingEncoding:NSUTF8StringEncoding];
    NSError *jsonError = nil;
    NSDictionary *rootDict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
    
    if (jsonError || !rootDict) {
        NSLog(@"[CLS Socket] ❌ JSON 解析失败：%@", jsonError);
        return @{};
    }
    
    // 11. 提取 GeoInfo 数据
    NSDictionary *geoInfoDict = rootDict[@"GeoInfo"];
    if (!geoInfoDict || geoInfoDict.count == 0) {
        NSLog(@"[CLS Socket] ❌ 响应中无 GeoInfo 字段");
        return @{};
    }
    
    NSLog(@"[CLS Socket] ✅ 成功获取网络信息");
    return @{
        @"usedNet": usedNet ?: @"unknown",
        @"defaultNet": [CLSDeviceUtils getNetworkTypeName] ?: @"unknown",
        @"client_ip": geoInfoDict[@"remote_addr"] ?: @"未知",
        @"country_id": geoInfoDict[@"country_code"] ?: @"未知",
        @"isp_en": geoInfoDict[@"provider"] ?: @"未知",
        @"province_en": geoInfoDict[@"province_name"] ?: @"未知",
        @"city_en": geoInfoDict[@"city_name"] ?: @"未知",
        @"country_en": geoInfoDict[@"country_name"] ?: @"未知",
    };
}

+ (NSString *)getSDKBuildTime {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss MMM d yyyy"];
    [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
    return [formatter stringFromDate:[NSDate date]];
}

#pragma mark - 辅助方法：映射蜂窝网络制式到3G/4G/5G
+ (NSString *)getCellularNetworkTypeWithRadioAccessTechnology:(NSString *)radioType {
    if (!radioType) return nil;
    
    // 映射关系：CoreTelephony的制式字符串 -> 3G/4G/5G
    NSDictionary *typeMap = @{
        // 5G（iOS 14.1+ 支持）
        CTRadioAccessTechnologyNR : @"5G",
        CTRadioAccessTechnologyNRNSA : @"5G", // 5G NSA（非独立组网）
        // 4G
        CTRadioAccessTechnologyLTE : @"4G",
        // 3G
        CTRadioAccessTechnologyWCDMA : @"3G",
        CTRadioAccessTechnologyHSDPA : @"3G",
        CTRadioAccessTechnologyHSUPA : @"3G",
        CTRadioAccessTechnologyCDMAEVDORev0 : @"3G",
        CTRadioAccessTechnologyCDMAEVDORevA : @"3G",
        CTRadioAccessTechnologyCDMAEVDORevB : @"3G",
        CTRadioAccessTechnologyeHRPD : @"3G",
        // 2G（如需区分可添加，当前需求仅3G/4G/5G，2G默认返回cellular）
        CTRadioAccessTechnologyGPRS : @"cellular",
        CTRadioAccessTechnologyEdge : @"cellular",
        CTRadioAccessTechnologyCDMA1x : @"cellular"
    };
    
    return typeMap[radioType] ?: @"cellular";
}

#pragma mark - 多网卡支持
+ (NSArray<NSDictionary *> *)getAllNetworkInterfacesDetail {
    NSMutableArray<NSDictionary *> *activeInterfaces = [NSMutableArray array];
    struct ifaddrs *allInterfaces = NULL;
    CTTelephonyNetworkInfo *networkInfo = [[CTTelephonyNetworkInfo alloc] init];
    NSString *currentRadioAccessTechnology = networkInfo.currentRadioAccessTechnology;
    
    if (getifaddrs(&allInterfaces) == 0) {
        struct ifaddrs *currentInterface = allInterfaces;
        
        while (currentInterface != NULL) {
            if (currentInterface->ifa_addr != NULL &&
                (currentInterface->ifa_addr->sa_family == AF_INET ||
                 currentInterface->ifa_addr->sa_family == AF_INET6)) {
                    
                NSString *interfaceName = [NSString stringWithUTF8String:currentInterface->ifa_name];
                unsigned int flags = currentInterface->ifa_flags;
                BOOL isInterfaceActive = ((flags & IFF_UP) && (flags & IFF_RUNNING));
                
                if (isInterfaceActive &&
                    ([interfaceName hasPrefix:@"en"] || [interfaceName hasPrefix:@"pdp_ip"])) {
                    
                    // ========== 核心：获取网卡下标（interface index） ==========
                    // if_nametoindex：通过网卡名称（如 en0、pdp_ip0）获取数字下标
                    unsigned int interfaceIndex = if_nametoindex(currentInterface->ifa_name);
                    // 兜底：若获取失败（返回0），标记为-1
                    NSInteger interfaceIndexFinal = interfaceIndex > 0 ? (NSInteger)interfaceIndex : -1;
                    
                    // 原有IP地址解析逻辑（不变）
                    char ipStr[INET6_ADDRSTRLEN];
                    const char *ipCString = "未知";
                    NSString *family = @"Unknown";
                    
                    if (currentInterface->ifa_addr->sa_family == AF_INET) {
                        struct sockaddr_in *ipv4 = (struct sockaddr_in *)currentInterface->ifa_addr;
                        inet_ntop(AF_INET, &(ipv4->sin_addr), ipStr, INET_ADDRSTRLEN);
                        ipCString = ipStr;
                        family = @"IPv4";
                    } else {
                        struct sockaddr_in6 *ipv6 = (struct sockaddr_in6 *)currentInterface->ifa_addr;
                        inet_ntop(AF_INET6, &(ipv6->sin6_addr), ipStr, INET6_ADDRSTRLEN);
                        ipCString = ipStr;
                        family = @"IPv6";
                    }
                    
                    NSString *ipAddress = [NSString stringWithUTF8String:ipCString];
                    
                    if (![ipAddress hasPrefix:@"127."] &&
                        ![ipAddress hasPrefix:@"fe80:"] &&
                        ![ipAddress hasPrefix:@"169.254"] &&
                        ![ipAddress isEqualToString:@"::1"] &&
                        ![ipAddress isEqualToString:@"未知"]) {
                        
                        NSString *interfaceType = [interfaceName hasPrefix:@"en"] ? @"wifi" : [self getCellularNetworkTypeWithRadioAccessTechnology:currentRadioAccessTechnology];
                        
                        // ========== 新增 "index" 字段返回网卡下标 ==========
                        [activeInterfaces addObject:@{
                            @"name": interfaceName,
                            @"index": @(interfaceIndexFinal), // 网卡下标（数字）
                            @"ip": ipAddress,
                            @"family": family,
                            @"type": interfaceType,
                            @"dns":[self getDNSAddressesForInterface:interfaceName]?:@""
                        }];
                    }
                }
            }
            currentInterface = currentInterface->ifa_next;
        }
        freeifaddrs(allInterfaces);
    }
    
    return [activeInterfaces copy];
}

#pragma mark - 新增辅助方法：获取指定接口的DNS地址
+ (NSString *)getDNSAddressesForInterface:(NSString *)interfaceName {
    NSMutableArray<NSString *> *dnsArray = [NSMutableArray array];
    res_state res = malloc(sizeof(struct __res_state));
    if (!res) return nil;
    
    memset(res, 0, sizeof(struct __res_state));
    int result = res_ninit(res);
    if (result == 0) {
        // 遍历DNS服务器列表
        for (int i = 0; i < res->nscount; i++) {
            struct sockaddr_in *sa4 = &res->nsaddr_list[i];
            struct sockaddr_in6 *sa6 = (struct sockaddr_in6 *)&res->nsaddr_list[i];
            char dnsStr[INET6_ADDRSTRLEN] = {0};
            
            if (sa4->sin_family == AF_INET) {
                // IPv4 DNS
                inet_ntop(AF_INET, &sa4->sin_addr, dnsStr, INET_ADDRSTRLEN);
            } else if (sa6->sin6_family == AF_INET6) {
                // IPv6 DNS
                inet_ntop(AF_INET6, &sa6->sin6_addr, dnsStr, INET6_ADDRSTRLEN);
            }
            
            NSString *dns = [NSString stringWithUTF8String:dnsStr];
            if (dns.length > 0 && ![dns isEqualToString:@"0.0.0.0"]) {
                [dnsArray addObject:dns];
            }
        }
        res_nclose(res);
    }
    free(res);
    
    // 拼接DNS地址为字符串（格式："ipv6,ipv6,ipv4"）
    return [dnsArray componentsJoinedByString:@","];
}

+ (NSArray<NSDictionary *> *)removeDuplicatesByInterface:(NSArray<NSDictionary *> *)allInterfaces {
    // 用于存储去重后的结果，键为接口名（如en0），值为该接口的信息字典
    NSMutableDictionary *interfaceDict = [NSMutableDictionary dictionary];
    
    for (NSDictionary *interfaceInfo in allInterfaces) {
        NSString *interfaceName = interfaceInfo[@"name"];
        NSDictionary *existingInterface = interfaceDict[interfaceName];
        
        // 如果这个网卡接口是第一次出现，直接存入
        if (!existingInterface) {
            interfaceDict[interfaceName] = interfaceInfo;
        } else {
            // 如果这个网卡接口已存在，则根据优先级决定保留哪一个
            // 规则示例：优先保留 IPv4 地址
            NSString *currentFamily = interfaceInfo[@"family"];
            NSString *existingFamily = existingInterface[@"family"];
            
            // 如果已存的是IPv6，但新的是IPv4，则用新的IPv4条目替换
            if ([existingFamily isEqualToString:@"IPv6"] && [currentFamily isEqualToString:@"IPv4"]) {
                interfaceDict[interfaceName] = interfaceInfo;
            }
            // 可以在此添加更多优先级规则，例如如果已存的是"未知"IP，新的是有效IP，则替换
        }
    }
    
    // 将字典中的所有值（即去重后的每个网卡信息）转换成数组返回
    return [interfaceDict allValues];
}

+ (NSArray<NSDictionary *> *)filterSingleInterfacePerType:(NSArray<NSDictionary *> *)allInterfaces {
    // 存储分组最优接口：key=接口大类(wifi/cellular)，value=该类最优接口信息
    NSMutableDictionary *categoryBestInterface = [NSMutableDictionary dictionary];
    
    for (NSDictionary *info in allInterfaces) {
        NSString *interfaceName = info[@"name"];
        NSString *family = info[@"family"];
        NSString *category = nil;
        
        // 1. 判断接口大类（Wi-Fi/蜂窝）
        if ([interfaceName hasPrefix:@"en"]) {
            category = @"wifi";
        } else if ([interfaceName hasPrefix:@"pdp_ip"]) {
            category = @"cellular";
        } else {
            continue; // 过滤非目标接口（如其他系统接口）
        }
        
        // 2. 该大类暂无最优接口，直接存入
        NSDictionary *existingBest = categoryBestInterface[category];
        if (!existingBest) {
            categoryBestInterface[category] = info;
            continue;
        }
        
        // 3. 该大类已有接口，按优先级替换（IPv4 > IPv6）
        NSString *existingFamily = existingBest[@"family"];
        if ([family isEqualToString:@"IPv4"] && [existingFamily isEqualToString:@"IPv6"]) {
            categoryBestInterface[category] = info;
        }
    }
    
    // 固定返回顺序：Wi-Fi在前，蜂窝在后（无则跳过）
    NSMutableArray *result = [NSMutableArray array];
    if (categoryBestInterface[@"wifi"]) {
        [result addObject:categoryBestInterface[@"wifi"]];
    }
    if (categoryBestInterface[@"cellular"]) {
        [result addObject:categoryBestInterface[@"cellular"]];
    }
    
    return result;
}

+ (NSArray<NSDictionary *> *)getAvailableInterfacesForType{
    NSArray *allInterfaces = [self getAllNetworkInterfacesDetail];
    NSArray *deduplicatedByInterface = [self removeDuplicatesByInterface:allInterfaces];
    NSArray *finalInterfaces = [self filterSingleInterfacePerType:deduplicatedByInterface];
    return finalInterfaces;
}

+ (NSString *)getIPAddressForInterface:(NSString *)interfaceName {
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    NSString *ipAddress = nil;
    
    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            // 检查接口名称和地址族（IPv4）
            if (temp_addr->ifa_addr->sa_family == AF_INET &&
                [[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:interfaceName]) {
                
                struct sockaddr_in *ipv4 = (struct sockaddr_in *)temp_addr->ifa_addr;
                char ip[INET_ADDRSTRLEN];
                inet_ntop(AF_INET, &(ipv4->sin_addr), ip, INET_ADDRSTRLEN);
                ipAddress = [NSString stringWithUTF8String:ip];
                break;
            }
            temp_addr = temp_addr->ifa_next;
        }
        freeifaddrs(interfaces);
    }
    
    return ipAddress;
}


//ping方法

struct IPHeader {
    uint8_t versionAndHeaderLength;
    uint8_t differentiatedServices;
    uint16_t totalLength;
    uint16_t identification;
    uint16_t flagsAndFragmentOffset;
    uint8_t timeToLive;
    uint8_t protocol;
    uint16_t headerChecksum;
    uint8_t sourceAddress[4];
    uint8_t destinationAddress[4];
    // options...
    // data...
};
typedef struct IPHeader IPHeader;

__Check_Compile_Time(sizeof(IPHeader) == 20);
__Check_Compile_Time(offsetof(IPHeader, versionAndHeaderLength) == 0);
__Check_Compile_Time(offsetof(IPHeader, differentiatedServices) == 1);
__Check_Compile_Time(offsetof(IPHeader, totalLength) == 2);
__Check_Compile_Time(offsetof(IPHeader, identification) == 4);
__Check_Compile_Time(offsetof(IPHeader, flagsAndFragmentOffset) == 6);
__Check_Compile_Time(offsetof(IPHeader, timeToLive) == 8);
__Check_Compile_Time(offsetof(IPHeader, protocol) == 9);
__Check_Compile_Time(offsetof(IPHeader, headerChecksum) == 10);
__Check_Compile_Time(offsetof(IPHeader, sourceAddress) == 12);
__Check_Compile_Time(offsetof(IPHeader, destinationAddress) == 16);

typedef struct ICMPPacket {
    uint8_t type;
    uint8_t code;
    uint16_t checksum;
    uint16_t identifier;
    uint16_t sequenceNumber;
    uint8_t payload[0]; // data, variable length
} ICMPPacket;

enum {
    kCLSICMPTypeEchoReply = 0,
    kCLSICMPTypeEchoRequest = 8
};

__Check_Compile_Time(sizeof(ICMPPacket) == 8);
__Check_Compile_Time(offsetof(ICMPPacket, type) == 0);
__Check_Compile_Time(offsetof(ICMPPacket, code) == 1);
__Check_Compile_Time(offsetof(ICMPPacket, checksum) == 2);
__Check_Compile_Time(offsetof(ICMPPacket, identifier) == 4);
__Check_Compile_Time(offsetof(ICMPPacket, sequenceNumber) == 6);

const int kCLSPacketSize = sizeof(ICMPPacket) + 100;

const int kCLSPacketBufferSize = 65535;

static uint16_t in_cksum(const void *buffer, size_t bufferLen)
// This is the standard BSD checksum code, modified to use modern types.
{
    size_t bytesLeft;
    int32_t sum;
    const uint16_t *cursor;
    union {
        uint16_t us;
        uint8_t uc[2];
    } last;
    uint16_t answer;

    bytesLeft = bufferLen;
    sum = 0;
    cursor = buffer;

    /*
     * Our algorithm is simple, using a 32 bit accumulator (sum), we add
     * sequential 16 bit words to it, and at the end, fold back all the
     * carry bits from the top 16 bits into the lower 16 bits.
     */
    while (bytesLeft > 1) {
        sum += *cursor;
        cursor += 1;
        bytesLeft -= 2;
    }

    /* mop up an odd byte, if necessary */
    if (bytesLeft == 1) {
        last.uc[0] = *(const uint8_t *)cursor;
        last.uc[1] = 0;
        sum += last.us;
    }

    /* add back carry outs from top 16 bits to low 16 bits */
    sum = (sum >> 16) + (sum & 0xffff); /* add hi 16 to low 16 */
    sum += (sum >> 16); /* add carry */
    answer = (uint16_t)~sum; /* truncate to 16 bits */

    return answer;
}

static ICMPPacket *build_packet(uint16_t seq, uint16_t identifier) {
    ICMPPacket *packet = (ICMPPacket *)calloc(kCLSPacketSize, 1);

    packet->type = kCLSICMPTypeEchoRequest; //设置回显请求报文
    packet->code = 0;
    packet->checksum = 0;
    packet->identifier = OSSwapHostToBigInt16(identifier); //标识符
    packet->sequenceNumber = OSSwapHostToBigInt16(seq);
    snprintf((char *)packet->payload, kCLSPacketSize - sizeof(ICMPPacket), "clslog ping test %d", (int)seq);
    packet->checksum = in_cksum(packet, kCLSPacketSize);
    return packet;
}

static char *icmpInPacket(char *packet, int len) {
    if (len < (sizeof(IPHeader) + sizeof(ICMPPacket))) {
        return NULL;
    }
    const struct IPHeader *ipPtr = (const IPHeader *)packet;
    if ((ipPtr->versionAndHeaderLength & 0xF0) != 0x40 // IPv4
        ||
        ipPtr->protocol != 1) { //ICMP
        return NULL;
    }
    size_t ipHeaderLength = (ipPtr->versionAndHeaderLength & 0x0F) * sizeof(uint32_t);

    if (len < ipHeaderLength + sizeof(ICMPPacket)) {
        return NULL;
    }

    return (char *)packet + ipHeaderLength;
}

static BOOL isValidResponse(char *buffer, int len, int seq, int identifier) {
    ICMPPacket *icmpPtr = (ICMPPacket *)icmpInPacket(buffer, len);
    if (icmpPtr == NULL) {
        return NO;
    }
    uint16_t receivedChecksum = icmpPtr->checksum;
    icmpPtr->checksum = 0;
    uint16_t calculatedChecksum = in_cksum(icmpPtr, len - ((char *)icmpPtr - buffer));

    return receivedChecksum == calculatedChecksum &&
           icmpPtr->type == kCLSICMPTypeEchoReply &&
           icmpPtr->code == 0 &&
           OSSwapBigToHostInt16(icmpPtr->identifier) == identifier &&
           OSSwapBigToHostInt16(icmpPtr->sequenceNumber) <= seq;
}

+ (int)sendPacket:(ICMPPacket *)packet
             sock:(int)sock
           target:(struct sockaddr_in *)addr {
    // 探测的数据包大小
    int size = 100;
    ssize_t sent = sendto(sock, packet, (size_t)size, 0, (struct sockaddr *)addr, (socklen_t)sizeof(struct sockaddr));
    if (sent < 0) {
        return errno;
    }
    return 0;
}

+ (NSInteger)ping:(struct sockaddr_in *)addr seq:(uint16_t)seq
       identifier:(uint16_t)identifier
             sock:(int)sock
              ttl:(int *)ttlOut
             size:(int *)size{
    ICMPPacket *packet = build_packet(seq, identifier);
    int err = 0;
    err = [self sendPacket:packet sock:sock target:addr];
    free(packet);
    if (err != 0) {
        return err;
    }

    struct sockaddr_storage ret_addr;
    socklen_t addrLen = sizeof(ret_addr);
    ;
    void *buffer = malloc(kCLSPacketBufferSize);

    ssize_t bytesRead = recvfrom(sock, buffer, kCLSPacketBufferSize, 0,
                                 (struct sockaddr *)&ret_addr, &addrLen);
    if (bytesRead < 0) {
        err = errno;
    } else if (bytesRead == 0) {
        err = EPIPE;
    } else {
        if (isValidResponse(buffer, (int)bytesRead, seq, identifier)) {
            *ttlOut = ((IPHeader *)buffer)->timeToLive;
            *size = (int)bytesRead;
        } else {
            err = -22001;
        }
    }
    free(buffer);
    return err;
    return 0;
}

+ (BOOL)bindSocket:(int)socket toInterface:(NSString *)interfaceName {
    if (!interfaceName || [interfaceName isEqualToString:@"auto"]) {
        return YES; // 不绑定特定接口
    }
    
    // 获取接口索引
    unsigned int interfaceIndex = if_nametoindex([interfaceName UTF8String]);
    if (interfaceIndex == 0) {
        return NO;
    }
    
    // 绑定socket到指定接口
    if (setsockopt(socket, IPPROTO_IP, IP_BOUND_IF, &interfaceIndex, sizeof(interfaceIndex)) < 0) {
        return NO;
    }
    
    return YES;
}

+ (NSDictionary *)buildEnhancedNetworkInfoWithInterfaceType:(NSString *)interfaceType
                                             networkAppId:(NSString *)networkAppId
                                                    appKey:(NSString *)appKey
                                                      uin:(NSString *)uin
                                                  endpoint:(NSString *)endpoint
                                             interfaceDNS:(NSString *)interfaceDNS
                                            interfaceName:(NSString *)interfaceName {
    // 1. 空值兜底（核心参数为空时返回空字典）
    if (!interfaceType) interfaceType = @"";
    
    // 2. 调用工具类获取基础网络信息（传递网卡名称）
    NSDictionary *baseNetworkInfo = [self getNetworkEnvironmentInfo:interfaceType
                                                                networkAppId:networkAppId
                                                                       appKey:appKey
                                                                           uin:uin
                                                                       endpoint:endpoint
                                                                 interfaceName:interfaceName];
    
    // 3. 构建增强网络信息（补充DNS）
    NSMutableDictionary *networkInfo = [NSMutableDictionary dictionaryWithDictionary:baseNetworkInfo ?: @{}];
    networkInfo[@"dns"] = interfaceDNS ?: @""; // DNS地址空值兜底
    
    return [networkInfo copy];
}

@end
