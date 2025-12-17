# 腾讯云日志服务 CLS iOS SDK

[![CocoaPods](https://img.shields.io/cocoapods/v/TencentCloudLogProducer.svg)](https://cocoapods.org/pods/TencentCloudLogProducer)
[![Platform](https://img.shields.io/cocoapods/p/TencentCloudLogProducer.svg)](https://cocoapods.org/pods/TencentCloudLogProducer)
[![License](https://img.shields.io/cocoapods/l/TencentCloudLogProducer.svg)](https://github.com/TencentCloud/tencentcloud-cls-sdk-ios/blob/main/LICENSE)

腾讯云日志服务（Cloud Log Service，CLS）iOS SDK 提供了高性能、可靠的日志上报和网络诊断能力。

## 📋 目录

- [功能特点](#功能特点)
- [环境要求](#环境要求)
- [安装](#安装)
- [快速开始](#快速开始)
- [日志上报](#日志上报)
- [网络诊断](#网络诊断)
- [API 文档](#api-文档)
- [示例代码](#示例代码)

---

## 🌟 功能特点

### Core 模块（日志上报）

* ✅ **异步上报** - 异步写入，客户端线程无阻塞
* ✅ **聚合&压缩** - 支持按超时时间、日志数、日志 size 聚合数据发送，支持 LZ4 压缩
* ✅ **本地缓存** - 基于 SQLite 的可靠缓存，支持缓存上限配置
* ✅ **断点续传** - 网络异常时自动缓存，网络恢复后自动重试
* ✅ **多主题** - 支持同时向多个日志主题上报数据

### NetWorkDiagnosis 模块（网络诊断）

* ✅ **HTTP Ping** - HTTP/HTTPS 请求探测，支持多网卡探测
* ✅ **TCP Ping** - TCP 端口连通性探测
* ✅ **ICMP Ping** - ICMP 协议 Ping，支持自定义包大小
* ✅ **DNS 解析** - DNS 查询测试，支持自定义 DNS 服务器
* ✅ **MTR 路由跟踪** - My TraceRoute 路由跟踪
* ✅ **自动上报** - 探测结果自动上报到 CLS

### 核心架构

![iOS 核心架构图](ios_sdk.jpg)

---

## 📦 环境要求

| 项目 | 要求 |
|------|------|
| iOS 版本 | iOS 10.0+ |
| Xcode 版本 | Xcode 12.0+ |
| 开发语言 | Objective-C / Swift |
| 包管理器 | CocoaPods 1.10.0+ |

---

## 🚀 安装

### 使用 CocoaPods

在 `Podfile` 中添加依赖：

```ruby
# 仅使用日志上报功能
pod 'TencentCloudLogProducer/Core', '~> 2.0.0'

# 使用日志上报 + 网络诊断功能
pod 'TencentCloudLogProducer/NetWorkDiagnosis', '~> 2.0.0'
```

然后执行：

```bash
pod install
```

---

## ⚡️ 快速开始

> ⚠️ **重要提示**：`LogSender` 是全局单例，应在应用启动时初始化一次（如在 `AppDelegate` 的 `application:didFinishLaunchingWithOptions:` 方法中），避免重复初始化。

### Objective-C

```objectivec
#import "TencentCloudLogProducer/ClsLogSender.h"
#import "TencentCloudLogProducer/ClsLogStorage.h"

// 1. 配置 SDK（⚠️ 仅在应用启动时初始化一次）
ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou.cls.tencentcs.com"
                                                         accessKeyId:@"YOUR_ACCESS_KEY_ID"
                                                           accessKey:@"YOUR_ACCESS_KEY"];
config.sendLogInterval = 5;  // 5秒发送一次
config.maxMemorySize = 32 * 1024 * 1024;  // 32MB 缓存上限

// 2. 启动 SDK（⚠️ 全局只启动一次）
LogSender *sender = [LogSender sharedSender];
[sender setConfig:config];
[sender start];

// 3. 写入日志
Log_Content *content = [Log_Content message];
content.key = @"message";
content.value = @"Hello CLS!";

Log *logItem = [Log message];
[logItem.contentsArray addObject:content];
logItem.time = (long long)([[NSDate date] timeIntervalSince1970]);

[[ClsLogStorage sharedInstance] writeLog:logItem
                                 topicId:@"YOUR_TOPIC_ID"
                              completion:^(BOOL success, NSError *error) {
    if (success) {
        NSLog(@"日志写入成功");
    } else {
        NSLog(@"日志写入失败: %@", error);
    }
}];
```

### Swift

```swift
import TencentCloudLogProducer

// 1. 配置 SDK（⚠️ 仅在应用启动时初始化一次）
let config = ClsLogSenderConfig(
    endpoint: "ap-guangzhou.cls.tencentcs.com",
    accessKeyId: "YOUR_ACCESS_KEY_ID",
    accessKey: "YOUR_ACCESS_KEY"
)
config.sendLogInterval = 5
config.maxMemorySize = 32 * 1024 * 1024

// 2. 启动 SDK（⚠️ 全局只启动一次）
let sender = LogSender.shared()
sender.setConfig(config)
sender.start()

// 3. 写入日志
let content = Log_Content()
content.key = "message"
content.value = "Hello CLS!"

let logItem = Log()
logItem.contentsArray.add(content)
logItem.time = Int64(Date().timeIntervalSince1970)

ClsLogStorage.sharedInstance().write(logItem, topicId: "YOUR_TOPIC_ID") { success, error in
    if success {
        print("日志写入成功")
    } else {
        print("日志写入失败: \(error?.localizedDescription ?? "")")
    }
}
```

---

## 📖 日志上报

> ⚠️ **重要提示**：`LogSender` 是全局单例，应在应用启动时（如 `AppDelegate` 的 `application:didFinishLaunchingWithOptions:` 方法中）初始化一次，避免重复初始化和启动。

### Core 模块配置

#### Objective-C 导入头文件

```objectivec
#import "TencentCloudLogProducer/ClsLogSender.h"
#import "TencentCloudLogProducer/ClsLogStorage.h"
#import "TencentCloudLogProducer/ClsLogModel.h"
#import "TencentCloudLogProducer/ClsLogs.pbobjc.h"
```

#### Swift 桥接头文件

在 `ProjectName-Bridging-Header.h` 中添加：

```objectivec
#import "TencentCloudLogProducer/ClsLogSender.h"
#import "TencentCloudLogProducer/ClsLogStorage.h"
#import "TencentCloudLogProducer/ClsLogModel.h"
#import "TencentCloudLogProducer/ClsLogs.pbobjc.h"
```

### 配置参数说明

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|-----|------|------|--------|------|
| `endpoint` | String | ✅ | - | 接入域名，如 `ap-guangzhou.cls.tencentcs.com`<br>参考：[地域列表](https://cloud.tencent.com/document/product/614/18940) |
| `accessKeyId` | String | ✅ | - | 访问密钥 ID<br>获取地址：[密钥管理](https://console.cloud.tencent.com/cam/capi) |
| `accessKey` | String | ✅ | - | 访问密钥 Key |
| `token` | String | ❌ | nil | 临时令牌（使用临时密钥时必填） |
| `sendLogInterval` | UInt64 | ❌ | 5 | 日志发送间隔（秒） |
| `maxMemorySize` | UInt64 | ❌ | 32MB | SDK 内存缓存上限（字节） |

> 💡 **权限要求**：确保密钥关联的账号具有 [SDK 上传日志权限](https://cloud.tencent.com/document/product/614/68374#.E4.BD.BF.E7.94.A8-api-.E4.B8.8A.E4.BC.A0.E6.95.B0.E6.8D.AE)

### 完整示例

> 💡 **最佳实践**：建议在 `AppDelegate` 中初始化 SDK，确保整个应用生命周期内只初始化一次。

#### Objective-C 示例

```objectivec
// 在 AppDelegate.m 中
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 1. 配置 SDK（⚠️ 全局只配置一次）
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou.cls.tencentcs.com"
                                                             accessKeyId:@"YOUR_ACCESS_KEY_ID"
                                                               accessKey:@"YOUR_ACCESS_KEY"];
    config.sendLogInterval = 5;  // 5秒发送一次
    config.maxMemorySize = 32 * 1024 * 1024;  // 32MB
    
    // 临时密钥（可选）
    // config.token = @"YOUR_TEMP_TOKEN";
    
    // 2. 启动 SDK（⚠️ 全局只启动一次）
    LogSender *sender = [LogSender sharedSender];
    [sender setConfig:config];
    [sender start];
    
    return YES;
}

// 在任意位置写入日志
- (void)someMethod {
// 在任意位置写入日志
- (void)someMethod {
    // 3. 构造日志内容
    Log_Content *content1 = [Log_Content message];
    content1.key = @"level";
    content1.value = @"INFO";
    
    Log_Content *content2 = [Log_Content message];
    content2.key = @"message";
    content2.value = @"用户登录成功";
    
    Log_Content *content3 = [Log_Content message];
    content3.key = @"userId";
    content3.value = @"12345";
    
    // 4. 创建日志项
    Log *logItem = [Log message];
    [logItem.contentsArray addObject:content1];
    [logItem.contentsArray addObject:content2];
    [logItem.contentsArray addObject:content3];
    logItem.time = (long long)([[NSDate date] timeIntervalSince1970]);
    
    // 5. 写入日志
    [[ClsLogStorage sharedInstance] writeLog:logItem
                                     topicId:@"YOUR_TOPIC_ID"
                                  completion:^(BOOL success, NSError *error) {
        if (success) {
            NSLog(@"✅ 日志写入成功");
        } else {
            NSLog(@"❌ 日志写入失败: %@", error.localizedDescription);
        }
    }];
}

// 应用退出时停止 SDK（可选）
- (void)applicationWillTerminate:(UIApplication *)application {
    [[LogSender sharedSender] stop];
}
```

#### Swift 示例

```swift
import TencentCloudLogProducer

// 在 AppDelegate.swift 中
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // 1. 配置 SDK（⚠️ 全局只配置一次）
    let config = ClsLogSenderConfig(
        endpoint: "ap-guangzhou.cls.tencentcs.com",
        accessKeyId: "YOUR_ACCESS_KEY_ID",
        accessKey: "YOUR_ACCESS_KEY"
    )
    config.sendLogInterval = 5
    config.maxMemorySize = 32 * 1024 * 1024
    
    // 临时密钥（可选）
    // config.token = "YOUR_TEMP_TOKEN"
    
    // 2. 启动 SDK（⚠️ 全局只启动一次）
    let sender = LogSender.shared()
    sender.setConfig(config)
    sender.start()
    
    return true
}

// 在任意位置写入日志
func someMethod() {
    // 3. 构造日志内容
    let content1 = Log_Content()
    content1.key = "level"
    content1.value = "INFO"
    
    let content2 = Log_Content()
    content2.key = "message"
    content2.value = "用户登录成功"
    
    let content3 = Log_Content()
    content3.key = "userId"
    content3.value = "12345"
    
    // 4. 创建日志项
    let logItem = Log()
    logItem.contentsArray.add(content1)
    logItem.contentsArray.add(content2)
    logItem.contentsArray.add(content3)
    logItem.time = Int64(Date().timeIntervalSince1970)
    
    // 5. 写入日志
    ClsLogStorage.sharedInstance().write(logItem, topicId: "YOUR_TOPIC_ID") { success, error in
        if success {
            print("✅ 日志写入成功")
        } else {
            print("❌ 日志写入失败: \(error?.localizedDescription ?? "")")
        }
    }
}

// 应用退出时停止 SDK（可选）
func applicationWillTerminate(_ application: UIApplication) {
    LogSender.shared().stop()
}
```

### 高级功能

#### 更新临时令牌

```objectivec
// Objective-C
[[LogSender sharedSender] updateToken:@"NEW_TEMP_TOKEN"];

// Swift
LogSender.shared().updateToken("NEW_TEMP_TOKEN")
```

#### 手动触发日志发送

```objectivec
// Objective-C
[[LogSender sharedSender] triggerSend];

// Swift
LogSender.shared().triggerSend()
```

#### 设置数据库大小限制

```objectivec
// Objective-C
[[ClsLogStorage sharedInstance] setMaxDatabaseSize:100 * 1024 * 1024];  // 100MB

// Swift
ClsLogStorage.sharedInstance().setMaxDatabaseSize(100 * 1024 * 1024)
```

---

## 🔍 网络诊断

NetWorkDiagnosis 模块提供全面的网络质量诊断能力，探测结果自动上报到 CLS。

### 安装配置

#### Podfile

```ruby
pod 'TencentCloudLogProducer/NetWorkDiagnosis', '~> 2.0.0'
```

#### Objective-C 导入头文件

```objectivec
#import "TencentCloudLogProducer/ClsNetworkDiagnosis.h"
#import "TencentCloudLogProducer/ClsLogSender.h"
```

### 初始化网络诊断

```objectivec
// 1. 配置日志上报
ClsLogSenderConfig *config = [[ClsLogSenderConfig alloc] init];
config.endpoint = @"ap-guangzhou.cls.tencentcs.com";
config.accessKeyId = @"YOUR_ACCESS_KEY_ID";
config.accessKey = @"YOUR_ACCESS_KEY";

// 2. 初始化网络诊断模块
[[ClsNetworkDiagnosis sharedInstance] setupLogSenderWithConfig:config];
```

### 探测功能说明

| 功能 | 说明 | 应用场景 |
|-----|------|---------|
| **HTTP Ping** | HTTP/HTTPS 请求探测 | 检测 Web 服务可达性、延迟 |
| **TCP Ping** | TCP 端口连通性探测 | 检测服务器端口可用性 |
| **ICMP Ping** | ICMP 协议 Ping | 网络连通性基础诊断 |
| **DNS 解析** | DNS 查询测试 | 域名解析故障排查 |
| **MTR 路由** | My TraceRoute 路由跟踪 | 网络路径分析 |

---

### 1️⃣ HTTP Ping（网页探测）

检测 HTTP/HTTPS 服务的可达性和响应时间，支持多网卡探测（WiFi + 蜂窝网络）。

#### 基础用法

```objectivec
// 创建请求
CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
request.domain = @"https://cloud.tencent.com/ping";
request.topicId = @"YOUR_TOPIC_ID";
request.appKey = @"YOUR_APP_KEY";

// 可选配置
request.maxTimes = 3;  // 探测次数
request.timeout = 10;  // 超时时间（秒）
request.enableMultiplePortsDetect = YES;  // 启用多网卡探测
request.enableSSLVerification = YES;  // 启用 SSL 验证

// 执行探测
[[ClsNetworkDiagnosis sharedInstance] httpingv2:request complate:^(CLSResponse *response) {
    if (response.success) {
        NSLog(@"✅ HTTP Ping 成功");
        NSLog(@"响应时间: %@ms", response.data[@"netInfo"][@"latency_avg"]);
    } else {
        NSLog(@"❌ HTTP Ping 失败: %@", response.errorMessage);
    }
}];
```

#### 自定义参数

```objectivec
CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
request.domain = @"https://api.example.com/health";
request.topicId = @"YOUR_TOPIC_ID";
request.appKey = @"YOUR_APP_KEY";

// 添加自定义参数
request.pageName = @"健康检查页面";
request.userEx = @{
    @"userId": @"12345",
    @"clientVersion": @"1.0.0"
};
request.detectEx = @{
    @"scene": @"startup",
    @"priority": @"high"
};

[[ClsNetworkDiagnosis sharedInstance] httpingv2:request complate:^(CLSResponse *response) {
    // 处理结果
}];
```

---

### 2️⃣ TCP Ping（端口探测）

检测 TCP 端口的连通性和连接时延。

#### 基础用法

```objectivec
// 创建请求
CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
request.domain = @"cloud.tencent.com";
request.port = 443;  // HTTPS 端口
request.topicId = @"YOUR_TOPIC_ID";
request.appKey = @"YOUR_APP_KEY";

// 可选配置
request.maxTimes = 5;  // 探测次数
request.timeout = 10;  // 超时时间（秒）
request.enableMultiplePortsDetect = YES;  // 多网卡探测

// 执行探测
[[ClsNetworkDiagnosis sharedInstance] tcpPingv2:request complate:^(CLSResponse *response) {
    if (response.success) {
        NSLog(@"✅ TCP Ping 成功");
        NSLog(@"平均延迟: %@ms", response.data[@"netInfo"][@"latency_avg"]);
        NSLog(@"成功率: %@%%", response.data[@"netInfo"][@"success_rate"]);
    } else {
        NSLog(@"❌ TCP Ping 失败: %@", response.errorMessage);
    }
}];
```

#### 常用端口

| 端口 | 协议 | 说明 |
|-----|------|------|
| 80 | HTTP | Web 服务 |
| 443 | HTTPS | 安全 Web 服务 |
| 3306 | MySQL | 数据库服务 |
| 6379 | Redis | 缓存服务 |
| 22 | SSH | 远程登录 |

---

### 3️⃣ ICMP Ping（网络连通性）

使用 ICMP 协议检测网络连通性和延迟。

#### 基础用法

```objectivec
// 创建请求
CLSPingRequest *request = [[CLSPingRequest alloc] init];
request.domain = @"cloud.tencent.com";
request.topicId = @"YOUR_TOPIC_ID";
request.appKey = @"YOUR_APP_KEY";

// 可选配置
request.maxTimes = 10;  // Ping 次数
request.size = 64;  // 数据包大小（字节）
request.timeout = 5;  // 超时时间（秒）
request.enableMultiplePortsDetect = YES;  // 多网卡探测

// 执行探测
[[ClsNetworkDiagnosis sharedInstance] pingv2:request complate:^(CLSResponse *response) {
    if (response.success) {
        NSLog(@"✅ Ping 成功");
        NSLog(@"最小/平均/最大延迟: %@/%@/%@ms",
              response.data[@"netInfo"][@"latency_min"],
              response.data[@"netInfo"][@"latency_avg"],
              response.data[@"netInfo"][@"latency_max"]);
        NSLog(@"丢包率: %@%%", response.data[@"netInfo"][@"loss_rate"]);
    } else {
        NSLog(@"❌ Ping 失败: %@", response.errorMessage);
    }
}];
```

---

### 4️⃣ DNS 解析

测试 DNS 域名解析功能，支持自定义 DNS 服务器。

#### 基础用法

```objectivec
// 创建请求
CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
request.domain = @"cloud.tencent.com";
request.topicId = @"YOUR_TOPIC_ID";
request.appKey = @"YOUR_APP_KEY";

// 可选：指定 DNS 服务器
// request.nameServer = @"8.8.8.8";  // Google DNS
// request.nameServer = @"119.29.29.29";  // DNSPod

// 执行解析
[[ClsNetworkDiagnosis sharedInstance] dns:request complate:^(CLSResponse *response) {
    if (response.success) {
        NSLog(@"✅ DNS 解析成功");
        NSLog(@"解析结果: %@", response.data[@"answerSection"]);
        NSLog(@"解析耗时: %@ms", response.data[@"netInfo"][@"latency_avg"]);
    } else {
        NSLog(@"❌ DNS 解析失败: %@", response.errorMessage);
    }
}];
```

#### 常用 DNS 服务器

| DNS 服务器 | 提供商 | 说明 |
|-----------|--------|------|
| 119.29.29.29 | DNSPod | 腾讯公共 DNS |
| 8.8.8.8 | Google | Google 公共 DNS |
| 114.114.114.114 | 114DNS | 国内公共 DNS |
| 1.1.1.1 | Cloudflare | Cloudflare DNS |

---

### 5️⃣ MTR 路由跟踪

My TraceRoute (MTR) 结合了 Traceroute 和 Ping 的功能，用于网络路径诊断。

#### 基础用法

```objectivec
// 创建请求
CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
request.domain = @"cloud.tencent.com";
request.topicId = @"YOUR_TOPIC_ID";
request.appKey = @"YOUR_APP_KEY";

// 可选配置
request.maxTimes = 30;  // 最大跳数
request.timeout = 60;  // 超时时间（秒）

// 执行 MTR
[[ClsNetworkDiagnosis sharedInstance] mtr:request complate:^(CLSResponse *response) {
    if (response.success) {
        NSLog(@"✅ MTR 探测成功");
        NSArray *paths = response.data[@"paths"];
        for (NSDictionary *hop in paths) {
            NSLog(@"跳数 %@: IP=%@, 延迟=%@ms",
                  hop[@"hop"],
                  hop[@"ip"],
                  hop[@"latency"]);
        }
    } else {
        NSLog(@"❌ MTR 失败: %@", response.errorMessage);
    }
}];
```

---

### 响应数据结构

所有探测方法返回的 `CLSResponse` 对象包含以下字段：

```objectivec
@interface CLSResponse : NSObject
@property (nonatomic, assign) BOOL success;           // 是否成功
@property (nonatomic, copy) NSString *errorMessage;   // 错误信息
@property (nonatomic, strong) NSDictionary *data;     // 探测结果数据
@end
```

#### 常见数据字段

| 字段 | 类型 | 说明 |
|-----|------|------|
| `netInfo` | Dictionary | 网络统计信息 |
| `netInfo.latency_avg` | Number | 平均延迟（ms） |
| `netInfo.latency_min` | Number | 最小延迟（ms） |
| `netInfo.latency_max` | Number | 最大延迟（ms） |
| `netInfo.loss_rate` | Number | 丢包率（%） |
| `netInfo.success_rate` | Number | 成功率（%） |
| `netOrigin` | Dictionary | 原始网络数据 |
| `detectEx` | Dictionary | 探测扩展字段 |
| `userEx` | Dictionary | 用户自定义字段 |

---

## 📚 API 文档

### Core 模块 API

#### ClsLogSenderConfig

日志发送器配置类。

```objectivec
@interface ClsLogSenderConfig : NSObject

// 必填参数
@property (nonatomic, copy, nonnull) NSString *endpoint;       // 接入域名
@property (nonatomic, copy, nonnull) NSString *accessKeyId;    // 访问密钥 ID
@property (nonatomic, copy, nonnull) NSString *accessKey;      // 访问密钥

// 可选参数
@property (nonatomic, copy, nullable) NSString *token;         // 临时令牌
@property (nonatomic, assign) uint64_t maxMemorySize;         // 内存上限（默认 32MB）
@property (nonatomic, assign) uint64_t sendLogInterval;       // 发送间隔（默认 5秒）

// 快速初始化
+ (nonnull instancetype)configWithEndpoint:(nonnull NSString *)endpoint
                              accessKeyId:(nonnull NSString *)accessKeyId
                                accessKey:(nonnull NSString *)accessKey;
@end
```

#### LogSender

日志发送器单例类。

```objectivec
@interface LogSender : NSObject

// 获取单例
+ (instancetype)sharedSender;

// 配置
- (void)setConfig:(nonnull ClsLogSenderConfig *)config;

// 启动/停止
- (void)start;
- (void)stop;

// 更新临时令牌
- (void)updateToken:(nullable NSString *)token;

// 手动触发发送
- (void)triggerSend;

@end
```

#### ClsLogStorage

日志存储管理类。

```objectivec
@interface ClsLogStorage : NSObject

// 获取单例
+ (instancetype)sharedInstance;

// 设置数据库大小上限
- (void)setMaxDatabaseSize:(uint64_t)maxSize;

// 写入日志
- (void)writeLog:(Log *)logItem
        topicId:(NSString *)topicId
      completion:(nullable void(^)(BOOL success, NSError * _Nullable error))completion;

// 查询待发送日志
- (NSArray<NSDictionary *> *)queryPendingLogs:(NSUInteger)limit;

// 删除已发送日志
- (void)deleteSentLogsWithIds:(NSArray<NSNumber *> *)logIds;

@end
```

---

### NetWorkDiagnosis 模块 API

#### ClsNetworkDiagnosis

网络诊断核心类。

```objectivec
@interface ClsNetworkDiagnosis : NSObject

// 获取单例
+ (instancetype)sharedInstance;

// 初始化配置
- (void)setupLogSenderWithConfig:(ClsLogSenderConfig *)config;

// HTTP Ping
- (void)httpingv2:(CLSHttpRequest *)request complate:(CompleteCallback)complate;

// TCP Ping
- (void)tcpPingv2:(CLSTcpRequest *)request complate:(CompleteCallback)complate;

// ICMP Ping
- (void)pingv2:(CLSPingRequest *)request complate:(CompleteCallback)complate;

// DNS 解析
- (void)dns:(CLSDnsRequest *)request complate:(CompleteCallback)complate;

// MTR 路由跟踪
- (void)mtr:(CLSMtrRequest *)request complate:(CompleteCallback)complate;

@end
```

#### 请求对象

**CLSRequest（基类）**

```objectivec
@interface CLSRequest : NSObject
@property (nonatomic, copy) NSString *topicId;                         // 日志主题 ID
@property (nonatomic, copy) NSString *domain;                          // 目标域名/IP
@property (nonatomic, copy) NSString *appKey;                          // 应用标识
@property (atomic, assign) int size;                                   // 数据包大小
@property (atomic, assign) int maxTimes;                               // 探测次数
@property (atomic, assign) int timeout;                                // 超时时间（秒）
@property (nonatomic, assign) BOOL enableMultiplePortsDetect;         // 启用多网卡探测
@property (nonatomic, copy, nullable) NSString *pageName;             // 页面名称
@property (nonatomic, strong) NSDictionary *userEx;                   // 用户自定义参数
@property (nonatomic, strong) NSDictionary *detectEx;                 // 探测扩展参数
@end
```

**CLSHttpRequest（HTTP 请求）**

```objectivec
@interface CLSHttpRequest : CLSRequest
@property (nonatomic, assign) BOOL enableSSLVerification;   // 启用 SSL 验证
@end
```

**CLSTcpRequest（TCP 请求）**

```objectivec
@interface CLSTcpRequest : CLSRequest
@property (atomic, assign) NSInteger port;   // 目标端口
@end
```

**CLSPingRequest（ICMP Ping 请求）**

```objectivec
@interface CLSPingRequest : CLSRequest
// 继承自 CLSRequest，无额外属性
@end
```

**CLSDnsRequest（DNS 请求）**

```objectivec
@interface CLSDnsRequest : CLSRequest
@property (nonatomic, copy) NSString *nameServer;   // DNS 服务器地址
@end
```

**CLSMtrRequest（MTR 请求）**

```objectivec
@interface CLSMtrRequest : CLSRequest
// 继承自 CLSRequest，无额外属性
@end
```

#### 响应对象

**CLSResponse**

```objectivec
@interface CLSResponse : NSObject
@property (nonatomic, assign) BOOL success;           // 是否成功
@property (nonatomic, copy) NSString *errorMessage;   // 错误信息
@property (nonatomic, strong) NSDictionary *data;     // 探测结果数据
@end
```

#### 回调类型

```objectivec
typedef void (^CompleteCallback)(CLSResponse *response);
```

---

## 💡 示例代码

### 完整示例：日志上报

```objectivec
#import "TencentCloudLogProducer/ClsLogSender.h"
#import "TencentCloudLogProducer/ClsLogStorage.h"

@implementation MyLogManager

- (void)setupCLS {
    // 配置
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou.cls.tencentcs.com"
                                                             accessKeyId:@"YOUR_ACCESS_KEY_ID"
                                                               accessKey:@"YOUR_ACCESS_KEY"];
    config.sendLogInterval = 5;
    config.maxMemorySize = 32 * 1024 * 1024;
    
    // 启动
    LogSender *sender = [LogSender sharedSender];
    [sender setConfig:config];
    [sender start];
    
    NSLog(@"✅ CLS 日志上报已启动");
}

- (void)logEvent:(NSString *)eventName params:(NSDictionary *)params {
    // 构造日志
    Log *logItem = [Log message];
    logItem.time = (long long)([[NSDate date] timeIntervalSince1970]);
    
    // 添加事件名称
    Log_Content *eventContent = [Log_Content message];
    eventContent.key = @"event";
    eventContent.value = eventName;
    [logItem.contentsArray addObject:eventContent];
    
    // 添加参数
    for (NSString *key in params) {
        Log_Content *content = [Log_Content message];
        content.key = key;
        content.value = [NSString stringWithFormat:@"%@", params[key]];
        [logItem.contentsArray addObject:content];
    }
    
    // 写入日志
    [[ClsLogStorage sharedInstance] writeLog:logItem
                                     topicId:@"YOUR_TOPIC_ID"
                                  completion:^(BOOL success, NSError *error) {
        if (!success) {
            NSLog(@"❌ 日志写入失败: %@", error);
        }
    }];
}

@end
```

### 完整示例：网络诊断

```objectivec
#import "TencentCloudLogProducer/ClsNetworkDiagnosis.h"

@implementation NetworkDiagnosisManager

- (void)setupNetworkDiagnosis {
    // 配置
    ClsLogSenderConfig *config = [[ClsLogSenderConfig alloc] init];
    config.endpoint = @"ap-guangzhou.cls.tencentcs.com";
    config.accessKeyId = @"YOUR_ACCESS_KEY_ID";
    config.accessKey = @"YOUR_ACCESS_KEY";
    
    // 初始化
    [[ClsNetworkDiagnosis sharedInstance] setupLogSenderWithConfig:config];
    
    NSLog(@"✅ 网络诊断模块已初始化");
}

- (void)diagnoseNetwork {
    // 1. HTTP Ping
    [self performHTTPPing];
    
    // 2. TCP Ping
    [self performTCPPing];
    
    // 3. ICMP Ping
    [self performICMPPing];
    
    // 4. DNS 解析
    [self performDNS];
    
    // 5. MTR 路由跟踪
    [self performMTR];
}

- (void)performHTTPPing {
    CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
    request.domain = @"https://cloud.tencent.com";
    request.topicId = @"YOUR_TOPIC_ID";
    request.appKey = @"YOUR_APP_KEY";
    request.maxTimes = 3;
    request.enableMultiplePortsDetect = YES;
    
    [[ClsNetworkDiagnosis sharedInstance] httpingv2:request complate:^(CLSResponse *response) {
        if (response.success) {
            NSLog(@"✅ HTTP Ping: 延迟 %@ms", response.data[@"netInfo"][@"latency_avg"]);
        } else {
            NSLog(@"❌ HTTP Ping 失败: %@", response.errorMessage);
        }
    }];
}

- (void)performTCPPing {
    CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
    request.domain = @"cloud.tencent.com";
    request.port = 443;
    request.topicId = @"YOUR_TOPIC_ID";
    request.appKey = @"YOUR_APP_KEY";
    request.maxTimes = 5;
    
    [[ClsNetworkDiagnosis sharedInstance] tcpPingv2:request complate:^(CLSResponse *response) {
        if (response.success) {
            NSLog(@"✅ TCP Ping: 延迟 %@ms, 成功率 %@%%",
                  response.data[@"netInfo"][@"latency_avg"],
                  response.data[@"netInfo"][@"success_rate"]);
        }
    }];
}

- (void)performICMPPing {
    CLSPingRequest *request = [[CLSPingRequest alloc] init];
    request.domain = @"cloud.tencent.com";
    request.topicId = @"YOUR_TOPIC_ID";
    request.appKey = @"YOUR_APP_KEY";
    request.maxTimes = 10;
    request.size = 64;
    
    [[ClsNetworkDiagnosis sharedInstance] pingv2:request complate:^(CLSResponse *response) {
        if (response.success) {
            NSLog(@"✅ ICMP Ping: 最小/平均/最大 %@/%@/%@ms, 丢包率 %@%%",
                  response.data[@"netInfo"][@"latency_min"],
                  response.data[@"netInfo"][@"latency_avg"],
                  response.data[@"netInfo"][@"latency_max"],
                  response.data[@"netInfo"][@"loss_rate"]);
        }
    }];
}

- (void)performDNS {
    CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
    request.domain = @"cloud.tencent.com";
    request.topicId = @"YOUR_TOPIC_ID";
    request.appKey = @"YOUR_APP_KEY";
    request.nameServer = @"119.29.29.29";  // DNSPod
    
    [[ClsNetworkDiagnosis sharedInstance] dns:request complate:^(CLSResponse *response) {
        if (response.success) {
            NSLog(@"✅ DNS 解析: %@, 耗时 %@ms",
                  response.data[@"answerSection"],
                  response.data[@"netInfo"][@"latency_avg"]);
        }
    }];
}

- (void)performMTR {
    CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
    request.domain = @"cloud.tencent.com";
    request.topicId = @"YOUR_TOPIC_ID";
    request.appKey = @"YOUR_APP_KEY";
    request.maxTimes = 30;
    
    [[ClsNetworkDiagnosis sharedInstance] mtr:request complate:^(CLSResponse *response) {
        if (response.success) {
            NSArray *paths = response.data[@"paths"];
            NSLog(@"✅ MTR 完成，共 %lu 跳", (unsigned long)paths.count);
        }
    }];
}

@end
```

---

## 🔗 相关链接

- [腾讯云日志服务官网](https://cloud.tencent.com/product/cls)
- [CLS 控制台](https://console.cloud.tencent.com/cls)
- [CLS 文档中心](https://cloud.tencent.com/document/product/614)
- [地域列表](https://cloud.tencent.com/document/product/614/18940)
- [API 权限配置](https://cloud.tencent.com/document/product/614/68374)
- [密钥管理](https://console.cloud.tencent.com/cam/capi)
- [GitHub 仓库](https://github.com/TencentCloud/tencentcloud-cls-sdk-ios)

---

## ❓ 常见问题

### 1. LogSender 应该在哪里初始化？

**✅ 推荐做法**：在 `AppDelegate` 的 `application:didFinishLaunchingWithOptions:` 方法中初始化一次。

```objectivec
// Objective-C
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"..."
                                                             accessKeyId:@"..."
                                                               accessKey:@"..."];
    [[LogSender sharedSender] setConfig:config];
    [[LogSender sharedSender] start];  // ⚠️ 只启动一次
    return YES;
}
```

**❌ 错误做法**：每次使用时都初始化或在多个地方重复初始化。

### 2. 可以多次调用 start() 吗？

**不建议**。`LogSender` 是单例模式，应该在应用启动时调用一次 `start()`。重复调用虽然不会崩溃，但可能导致资源浪费和不可预期的行为。

### 3. 如何获取 Topic ID？

登录 [CLS 控制台](https://console.cloud.tencent.com/cls/logset/desc)，在日志主题页面查看主题 ID。

### 4. 日志上报失败怎么办？

检查以下几点：
- ✅ 确认 `accessKeyId` 和 `accessKey` 正确
- ✅ 确认密钥有 CLS 上传权限
- ✅ 确认 `endpoint` 地域正确
- ✅ 确认 `topicId` 存在且有效
- ✅ 检查网络连接

### 5. 如何调试 SDK？

SDK 内部使用 `NSLog` 输出调试信息，可以在 Xcode Console 查看。

### 6. 支持 IPv6 吗？

是的，SDK 完全支持 IPv6 网络环境。

### 7. 多网卡探测是什么？

当设备同时连接 WiFi 和蜂窝网络时，开启 `enableMultiplePortsDetect` 可以分别通过两个网卡进行探测，帮助诊断网络问题。

### 8. 如何处理临时密钥过期？

使用 `updateToken:` 方法动态更新临时令牌：

```objectivec
[[LogSender sharedSender] updateToken:@"NEW_TEMP_TOKEN"];
```

### 9. 日志会丢失吗？

不会。SDK 采用本地 SQLite 数据库缓存，网络异常时日志会保存在本地，网络恢复后自动重试上报。

---

## 📄 License

本项目采用 [MIT License](LICENSE)。

---

## 🤝 技术支持

如有问题，请通过以下方式联系我们：

- 📧 提交 [GitHub Issue](https://github.com/TencentCloud/tencentcloud-cls-sdk-ios/issues)
- 📞 联系腾讯云客服
- 💬 加入腾讯云技术交流群




