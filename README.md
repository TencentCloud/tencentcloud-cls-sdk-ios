# 腾讯云日志服务 CLS iOS SDK

[![CocoaPods](https://img.shields.io/cocoapods/v/TencentCloudLogProducer.svg)](https://cocoapods.org/pods/TencentCloudLogProducer)
[![Platform](https://img.shields.io/cocoapods/p/TencentCloudLogProducer.svg)](https://cocoapods.org/pods/TencentCloudLogProducer)
[![License](https://img.shields.io/cocoapods/l/TencentCloudLogProducer.svg)](https://github.com/TencentCloud/tencentcloud-cls-sdk-ios/blob/main/LICENSE)
[![iOS Version](https://img.shields.io/badge/iOS-12.0%2B-blue.svg)](https://developer.apple.com/ios/)

腾讯云日志服务（Cloud Log Service，CLS）iOS SDK 提供了企业级的**日志上报**和**网络诊断**能力，帮助开发者轻松实现应用日志收集、性能监控和网络质量分析。

---

## 📋 目录

- [功能特点](#-功能特点)
- [最新更新](#-最新更新)
- [环境要求](#-环境要求)
- [安装指南](#-安装指南)
- [快速开始](#-快速开始)
- [日志上报](#-日志上报)
  - [基础配置](#基础配置)
  - [初始化 SDK](#初始化-sdk)
  - [写入日志](#写入日志)
  - [高级配置](#高级配置)
- [网络诊断](#-网络诊断)
  - [初始化配置](#初始化配置)
  - [HTTP Ping](#1-http-ping)
  - [TCP Ping](#2-tcp-ping)
  - [ICMP Ping](#3-icmp-ping)
  - [DNS 解析](#4-dns-解析)
  - [MTR 路由跟踪](#5-mtr-路由跟踪)
  - [IP 协议偏好控制](#ip-协议偏好控制)
- [API 参考](#-api-参考)
- [示例项目](#-示例项目)
- [常见问题](#-常见问题)
- [性能指标](#-性能指标)
- [最佳实践](#-最佳实践)
- [更新日志](#-更新日志)
- [技术支持](#-技术支持)

---

## 🌟 功能特点

### 📊 日志上报模块

- ✅ **高性能上报**：异步写入、批量发送、LZ4 压缩（平均压缩率 70%）
- ✅ **本地缓存**：SQLite 持久化存储，断点续传，最大 32MB 可配置
- ✅ **可靠传输**：网络异常自动保留日志，支持重试机制
- ✅ **多 Topic 支持**：单 SDK 实例支持多个日志主题
- ✅ **标准协议**：基于 Protobuf 序列化，符合 CLS 规范

### 🌐 网络诊断模块

- ✅ **5 种探测方式**：HTTP Ping、TCP Ping、ICMP Ping、DNS 解析、MTR 路由跟踪
- ✅ **多网卡探测**：支持 WiFi/蜂窝网络并发探测，单独统计
- ✅ **IPv4/IPv6 控制**：支持协议偏好设置（v3.0.0 新增）
- ✅ **详细指标**：15+ 个 HTTP 生命周期时间点、完整 TCP/ICMP 统计
- ✅ **底层实现**：基于 C 语言实现，高性能、低开销
- ✅ **OpenTelemetry 兼容**：符合 OTLP Span 数据格式

### 🔐 企业级特性

- ✅ **隐私合规**：包含 PrivacyInfo.xcprivacy 清单文件
- ✅ **安全认证**：支持永久密钥和 STS 临时密钥
- ✅ **完整测试**：50+ 测试用例，覆盖各种网络环境
- ✅ **中文文档**：详细的中文文档和示例代码

---

## 🎉 最新更新

### v3.0.0 (发布)

#### 🆕 新增功能

**1. IPv4/IPv6 协议偏好控制**
- ✅ Ping、DNS、MTR 探测支持 IP 协议偏好设置
- ✅ 新增 `prefer` 参数：支持 IPv4/IPv6 优先、仅 IPv4/IPv6、自动检测
- ✅ 适配双栈网络环境，提供更灵活的网络诊断能力

**2. 初始化方式优化**
- ✅ 支持 `topicId` 和 `netToken` 两种初始化方式
- ✅ netToken 自动提前解析并缓存，避免重复解析
- ✅ 性能提升：解析次数减少 99%+

**3. 测试覆盖增强**
- ✅ 新增 14 个测试用例（IPv4/IPv6 偏好测试 9 个 + topicId 模式测试 5 个）
- ✅ 覆盖各种网络环境和协议场景

#### 🐛 修复

- 🔧 修复多网卡探测时网卡绑定失败的问题
- 🔧 优化 netToken 解析性能，避免每次探测重复解析

---

## 📱 环境要求

| 项目 | 要求 |
|------|------|
| **iOS 版本** | iOS 12.0+ |
| **Xcode** | Xcode 13.0+ |
| **语言** | Objective-C / Swift 5.0+ |
| **架构** | arm64, x86_64 (模拟器) |
| **依赖管理** | CocoaPods 1.10.0+ |

### 系统依赖

- Foundation.framework
- SystemConfiguration.framework
- UIKit.framework
- CoreTelephony.framework（网络诊断模块）
- Network.framework（网络诊断模块，iOS 12+）
- libz.tbd（数据压缩）
- libsqlite3.tbd（本地存储）
- libresolv.tbd（DNS 解析）

---

## 📦 安装指南

### 方式一：CocoaPods（推荐）

#### 1. 仅日志上报功能

如果只需要日志上报功能，安装 Core 子模块：

```ruby
# Podfile
platform :ios, '12.0'
use_frameworks! # 可选，推荐

target 'YourApp' do
  pod 'TencentCloudLogProducer/Core', '~> 3.0.0'
end
```

#### 2. 日志上报 + 网络诊断（推荐）

如果需要完整功能，安装 NetWorkDiagnosis 子模块（会自动包含 Core）：

```ruby
# Podfile
platform :ios, '12.0'
use_frameworks! # 可选，推荐

target 'YourApp' do
  pod 'TencentCloudLogProducer/NetWorkDiagnosis', '~> 3.0.0'
end
```

#### 3. 安装依赖

```bash
cd YourProjectDirectory
pod install
```

打开生成的 `.xcworkspace` 文件：

```bash
open YourApp.xcworkspace
```

### 方式二：手动集成

#### 1. 下载 SDK

从 [GitHub Releases](https://github.com/TencentCloud/tencentcloud-cls-sdk-ios/releases) 下载最新版本。

#### 2. 导入文件

将 `TencentCloudLogProducer` 文件夹拖入项目，并勾选：
- ✅ Copy items if needed
- ✅ Create groups

#### 3. 添加依赖

手动添加以下依赖库：
- Protobuf (~> 3.29.5)
- FMDB (~> 2.7.5)
- Reachability (~> 3.7)

#### 4. 配置系统库

在 **Build Phases → Link Binary With Libraries** 中添加：
- Foundation.framework
- SystemConfiguration.framework
- UIKit.framework
- CoreTelephony.framework（网络诊断）
- Network.framework（网络诊断）
- libz.tbd
- libsqlite3.tbd
- libresolv.tbd（网络诊断）

---

## 🚀 快速开始

### Objective-C 项目

#### 1. 导入头文件

```objectivec
// 日志上报
#import <TencentCloudLogProducer/ClsLogSender.h>
#import <TencentCloudLogProducer/ClsLogStorage.h>
#import <TencentCloudLogProducer/ClsLogs.pbobjc.h>

// 网络诊断（如果安装了 NetWorkDiagnosis 子模块）
#import <TencentCloudLogProducer/ClsNetworkDiagnosis.h>
```

#### 2. 在 AppDelegate 中初始化

```objectivec
// AppDelegate.m
#import "AppDelegate.h"
#import <TencentCloudLogProducer/ClsLogSender.h>
#import <TencentCloudLogProducer/ClsLogStorage.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application 
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    // 配置日志上报
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou.cls.tencentcs.com"
                                                         accessKeyId:@"YOUR_ACCESS_KEY_ID"
                                                           accessKey:@"YOUR_ACCESS_KEY"];
    config.sendLogInterval = 5;  // 发送间隔 5 秒
    config.maxMemorySize = 32 * 1024 * 1024;  // 最大 32MB
    
    // 初始化并启动
    LogSender *sender = [LogSender sharedSender];
    [sender setConfig:config];
    [sender start];
    
    return YES;
}

@end
```

#### 3. 写入日志

```objectivec
// 创建日志内容
Log_Content *content1 = [Log_Content message];
content1.key = @"level";
content1.value = @"INFO";

Log_Content *content2 = [Log_Content message];
content2.key = @"message";
content2.value = @"用户点击了登录按钮";

// 创建日志项
Log *logItem = [Log message];
[logItem.contentsArray addObject:content1];
[logItem.contentsArray addObject:content2];
logItem.time = (long long)([[NSDate date] timeIntervalSince1970]);

// 写入日志（异步）
[[ClsLogStorage sharedInstance] writeLog:logItem
                                 topicId:@"YOUR_TOPIC_ID"
                              completion:^(BOOL success, NSError *error) {
    if (success) {
        NSLog(@"✅ 日志写入成功");
    } else {
        NSLog(@"❌ 日志写入失败: %@", error.localizedDescription);
    }
}];
```

### Swift 项目

#### 1. 创建桥接头文件

创建 `YourProject-Bridging-Header.h` 文件：

```objectivec
// YourProject-Bridging-Header.h
#ifndef YourProject_Bridging_Header_h
#define YourProject_Bridging_Header_h

#import <TencentCloudLogProducer/ClsLogSender.h>
#import <TencentCloudLogProducer/ClsLogStorage.h>
#import <TencentCloudLogProducer/ClsLogs.pbobjc.h>
#import <TencentCloudLogProducer/ClsNetworkDiagnosis.h>

#endif
```

在 **Build Settings** 中设置桥接头文件路径：
- **Objective-C Bridging Header**: `$(PROJECT_DIR)/YourProject/YourProject-Bridging-Header.h`

#### 2. 在 AppDelegate 中初始化

```swift
// AppDelegate.swift
import UIKit
import TencentCloudLogProducer

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, 
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // 配置日志上报
        let config = ClsLogSenderConfig(
            endpoint: "ap-guangzhou.cls.tencentcs.com",
            accessKeyId: "YOUR_ACCESS_KEY_ID",
            accessKey: "YOUR_ACCESS_KEY"
        )
        config?.sendLogInterval = 5  // 发送间隔 5 秒
        config?.maxMemorySize = 32 * 1024 * 1024  // 最大 32MB
        
        // 初始化并启动
        let sender = LogSender.shared()
        sender?.setConfig(config)
        sender?.start()
        
        return true
    }
}
```

#### 3. 写入日志

```swift
import UIKit
import TencentCloudLogProducer

class ViewController: UIViewController {
    
    func logEvent() {
        // 创建日志内容
        let content1 = Log_Content()
        content1.key = "level"
        content1.value = "INFO"
        
        let content2 = Log_Content()
        content2.key = "message"
        content2.value = "用户点击了登录按钮"
        
        // 创建日志项
        let logItem = Log()
        logItem.contentsArray.add(content1)
        logItem.contentsArray.add(content2)
        logItem.time = Int64(Date().timeIntervalSince1970)
        
        // 写入日志（异步）
        ClsLogStorage.sharedInstance().write(logItem, topicId: "YOUR_TOPIC_ID") { success, error in
            if success {
                print("✅ 日志写入成功")
            } else {
                print("❌ 日志写入失败: \(error?.localizedDescription ?? "")")
            }
        }
    }
}
```

---

## 📊 日志上报

### 基础配置

#### ClsLogSenderConfig 配置项

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `endpoint` | NSString | ✅ | - | CLS 接入点，如 `ap-guangzhou.cls.tencentcs.com` |
| `accessKeyId` | NSString | ✅ | - | 腾讯云访问密钥 ID（永久密钥或临时密钥） |
| `accessKey` | NSString | ✅ | - | 腾讯云访问密钥 Key |
| `token` | NSString | ❌ | nil | STS 临时令牌（使用临时密钥时必填） |
| `sendLogInterval` | uint64_t | ❌ | 5 | 日志发送间隔（秒），范围 1-60 |
| `maxMemorySize` | uint64_t | ❌ | 33554432 | 本地数据库最大容量（字节），默认 32MB |

#### 地域接入点列表

| 地域 | Endpoint |
|------|----------|
| 广州 | `ap-guangzhou.cls.tencentcs.com` |
| 上海 | `ap-shanghai.cls.tencentcs.com` |
| 北京 | `ap-beijing.cls.tencentcs.com` |
| 成都 | `ap-chengdu.cls.tencentcs.com` |
| 南京 | `ap-nanjing.cls.tencentcs.com` |
| 重庆 | `ap-chongqing.cls.tencentcs.com` |
| 香港 | `ap-hongkong.cls.tencentcs.com` |
| 硅谷 | `na-siliconvalley.cls.tencentcs.com` |
| 弗吉尼亚 | `na-ashburn.cls.tencentcs.com` |
| 新加坡 | `ap-singapore.cls.tencentcs.com` |
| 东京 | `ap-tokyo.cls.tencentcs.com` |
| 孟买 | `ap-mumbai.cls.tencentcs.com` |
| 首尔 | `ap-seoul.cls.tencentcs.com` |
| 法兰克福 | `eu-frankfurt.cls.tencentcs.com` |
| 多伦多 | `na-toronto.cls.tencentcs.com` |
| 圣保罗 | `sa-saopaulo.cls.tencentcs.com` |

> 💡 **提示**：选择离用户最近的地域可以降低上报延迟。

### 初始化 SDK

#### 方式一：使用永久密钥（推荐用于测试）

```objectivec
ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou.cls.tencentcs.com"
                                                     accessKeyId:@"YOUR_ACCESS_KEY_ID"
                                                       accessKey:@"YOUR_ACCESS_KEY"];
LogSender *sender = [LogSender sharedSender];
[sender setConfig:config];
[sender start];
```

#### 方式二：使用 STS 临时密钥（推荐用于生产）

```objectivec
ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou.cls.tencentcs.com"
                                                     accessKeyId:@"YOUR_TEMP_ACCESS_KEY_ID"
                                                       accessKey:@"YOUR_TEMP_ACCESS_KEY"];
config.token = @"YOUR_STS_TOKEN";  // 临时令牌

LogSender *sender = [LogSender sharedSender];
[sender setConfig:config];
[sender start];

// 定期更新临时令牌（如每 30 分钟）
dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * 60 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [sender updateToken:@"NEW_STS_TOKEN"];
});
```

> 🔐 **安全建议**：
> - ❌ **不要**将永久密钥硬编码在客户端代码中
> - ✅ **推荐**使用 STS 临时密钥，定期从服务器获取
> - ✅ 参考[腾讯云 STS 文档](https://cloud.tencent.com/document/product/598/33416)

### 写入日志

#### 1. 基本用法

```objectivec
// 创建日志内容（Key-Value 键值对）
Log_Content *content = [Log_Content message];
content.key = @"message";
content.value = @"这是一条测试日志";

// 创建日志项
Log *logItem = [Log message];
[logItem.contentsArray addObject:content];
logItem.time = (long long)([[NSDate date] timeIntervalSince1970]);

// 写入日志
[[ClsLogStorage sharedInstance] writeLog:logItem
                                 topicId:@"YOUR_TOPIC_ID"
                              completion:^(BOOL success, NSError *error) {
    // 处理结果
}];
```

#### 2. 多字段日志

```objectivec
Log *logItem = [Log message];

// 添加多个字段
NSArray *fields = @[
    @[@"level", @"ERROR"],
    @[@"module", @"NetworkModule"],
    @[@"error_code", @"500"],
    @[@"message", @"网络请求失败"],
    @[@"user_id", @"12345"],
    @[@"timestamp", @"2025-02-09T10:30:00Z"]
];

for (NSArray *field in fields) {
    Log_Content *content = [Log_Content message];
    content.key = field[0];
    content.value = field[1];
    [logItem.contentsArray addObject:content];
}

logItem.time = (long long)([[NSDate date] timeIntervalSince1970]);

[[ClsLogStorage sharedInstance] writeLog:logItem topicId:@"YOUR_TOPIC_ID" completion:nil];
```

#### 3. 批量写入（高性能场景）

```objectivec
// 批量写入 1000 条日志
for (int i = 0; i < 1000; i++) {
    Log_Content *content = [Log_Content message];
    content.key = @"message";
    content.value = [NSString stringWithFormat:@"日志 #%d", i];
    
    Log *logItem = [Log message];
    [logItem.contentsArray addObject:content];
    logItem.time = (long long)([[NSDate date] timeIntervalSince1970]);
    
    // 异步写入（不阻塞主线程）
    [[ClsLogStorage sharedInstance] writeLog:logItem topicId:@"YOUR_TOPIC_ID" completion:nil];
}
```

> ⚡ **性能提示**：
> - 写入操作是**异步**的，不会阻塞主线程
> - SDK 会自动批量发送（每 5 秒一次）
> - 单次批量最多 100 条日志
> - 单日志大小不超过 512KB
> - 聚合包大小不超过 5MB

### 高级配置

#### 1. 自定义发送间隔

```objectivec
ClsLogSenderConfig *config = [[ClsLogSenderConfig alloc] init];
config.endpoint = @"ap-guangzhou.cls.tencentcs.com";
config.accessKeyId = @"YOUR_ACCESS_KEY_ID";
config.accessKey = @"YOUR_ACCESS_KEY";
config.sendLogInterval = 3;  // 3 秒发送一次（高频场景）

LogSender *sender = [LogSender sharedSender];
[sender setConfig:config];
[sender start];
```

#### 2. 自定义数据库容量

```objectivec
ClsLogSenderConfig *config = [[ClsLogSenderConfig alloc] init];
config.endpoint = @"ap-guangzhou.cls.tencentcs.com";
config.accessKeyId = @"YOUR_ACCESS_KEY_ID";
config.accessKey = @"YOUR_ACCESS_KEY";
config.maxMemorySize = 64 * 1024 * 1024;  // 64MB（大容量场景）

LogSender *sender = [LogSender sharedSender];
[sender setConfig:config];
[sender start];
```

#### 3. 停止日志上报

```objectivec
// 停止后台发送线程
[[LogSender sharedSender] stop];

// 重新启动
[[LogSender sharedSender] start];
```

### 日志上报流程

```
应用代码
  │
  ├─ writeLog:topicId:completion:
  │    └─ ClsLogStorage（异步写入 SQLite）
  │         ├─ 检查数据库大小（超容则删除最早日志）
  │         ├─ Protobuf 序列化
  │         └─ Base64 编码存储
  │
  ├─ LogSender（后台线程，5 秒定时触发）
  │    ├─ queryPendingLogs:100（查询待发送日志）
  │    ├─ 按 topicId 分组
  │    ├─ 检查单日志大小（512KB 上限）
  │    ├─ 检查聚合包大小（5MB 上限）
  │    ├─ 构建 LogGroupList
  │    ├─ LZ4 压缩（平均压缩率 70%）
  │    ├─ 生成腾讯云签名
  │    └─ HTTPS POST 上报
  │         ├─ 成功（200）：删除已发送日志
  │         ├─ 保留（<0, 5xx, 429）：网络错误/服务器错误/限流
  │         └─ 删除（400, 404）：客户端错误，重试无意义
  │
  └─ CLS 云端接收
```

---

## 🌐 网络诊断

网络诊断模块提供 **5 种探测方式**，帮助分析应用的网络性能和质量问题。

### 初始化配置

#### 方式一：使用 topicId（推荐）

```objectivec
// 1. 配置日志上报（与日志上报共用）
ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou-open.cls.tencentcs.com"
                                                     accessKeyId:@"YOUR_ACCESS_KEY_ID"
                                                       accessKey:@"YOUR_ACCESS_KEY"];

// 2. 初始化网络诊断
[[ClsNetworkDiagnosis sharedInstance] setupLogSenderWithConfig:config 
                                                       topicId:@"YOUR_TOPIC_ID"];

// 3. 设置全局扩展字段（可选）
[[ClsNetworkDiagnosis sharedInstance] setUserEx:@{
    @"app_version": @"1.0.0",
    @"user_id": @"12345"
}];
```

#### 方式二：使用 netToken

```objectivec
// 1. 配置日志上报
ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou-open.cls.tencentcs.com"
                                                     accessKeyId:@"YOUR_ACCESS_KEY_ID"
                                                       accessKey:@"YOUR_ACCESS_KEY"];

// 2. 初始化网络诊断（使用 netToken）
NSString *netToken = @"YOUR_NET_TOKEN";  // Base64 编码的 JSON，包含 networkAppId/appKey/topic_id
[[ClsNetworkDiagnosis sharedInstance] setupLogSenderWithConfig:config 
                                                      netToken:netToken];

// 3. 设置全局扩展字段（可选）
[[ClsNetworkDiagnosis sharedInstance] setUserEx:@{
    @"scene": @"homepage"
}];
```

> 💡 **提示**：
> - `topicId` 方式更简单，推荐使用
> - `netToken` 方式适合多租户场景，SDK 会自动解析并缓存

### 1. HTTP Ping

测量 HTTP/HTTPS 请求的完整生命周期，包含 **15 个时间点**：DNS 解析、TCP 连接、SSL 握手、请求发送、响应接收等。

#### 基本用法

```objectivec
// 创建请求
CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
request.domain = @"https://cloud.tencent.com";  // 完整 URL
request.appKey = @"YOUR_APP_KEY";
request.maxTimes = 3;  // 探测 3 次
request.timeout = 10000;  // 超时 10 秒

// 执行探测
[[ClsNetworkDiagnosis sharedInstance] httpingv2:request complate:^(CLSResponse *response) {
    if (response.success) {
        NSLog(@"✅ HTTP Ping 成功");
        NSLog(@"结果: %@", response.content);  // JSON 格式
        
        // 解析结果
        NSDictionary *data = response.data;
        NSDictionary *netOrigin = data[@"netOrigin"];
        
        NSNumber *dnsTime = netOrigin[@"dns_time"];  // DNS 耗时（毫秒）
        NSNumber *tcpConnectTime = netOrigin[@"tcp_connect_time"];  // TCP 连接耗时
        NSNumber *sslHandshakeTime = netOrigin[@"ssl_handshake_time"];  // SSL 握手耗时
        NSNumber *totalTime = netOrigin[@"total_time"];  // 总耗时
        
        NSLog(@"DNS: %@ms, TCP: %@ms, SSL: %@ms, 总计: %@ms", 
              dnsTime, tcpConnectTime, sslHandshakeTime, totalTime);
    } else {
        NSLog(@"❌ HTTP Ping 失败: %@", response.errorMessage);
    }
}];
```

#### 高级配置

```objectivec
CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
request.domain = @"https://api.example.com/health";
request.appKey = @"YOUR_APP_KEY";
request.maxTimes = 5;
request.timeout = 15000;

// 多网卡探测（WiFi + 蜂窝网络并发）
request.enableMultiplePortsDetect = YES;

// 扩展字段（自定义业务标识）
request.detectEx = @{
    @"api_name": @"/health",
    @"request_id": @"req_12345"
};

// 页面名称（用于分组统计）
request.pageName = @"HomePage";

// 追踪 ID（关联多个探测）
request.traceId = [[NSUUID UUID] UUIDString];

// SSL 证书验证（默认开启）
request.enableSSLVerification = YES;

[[ClsNetworkDiagnosis sharedInstance] httpingv2:request complate:^(CLSResponse *response) {
    // 处理结果
}];
```

#### HTTP 生命周期时间点

| 时间点 | 字段名 | 说明 |
|--------|--------|------|
| 1 | `callStart` | 开始调用 |
| 2 | `dnsStart` | DNS 解析开始 |
| 3 | `dnsEnd` | DNS 解析结束 |
| 4 | `connectStart` | TCP 连接开始 |
| 5 | `secureConnectStart` | SSL 握手开始 |
| 6 | `secureConnectEnd` | SSL 握手结束 |
| 7 | `connectionAcquired` | TCP 连接建立 |
| 8 | `requestHeaderStart` | 请求头发送开始 |
| 9 | `requestHeaderEnd` | 请求头发送结束 |
| 10 | `requestBodyStart` | 请求体发送开始 |
| 11 | `requestBodyEnd` | 请求体发送结束 |
| 12 | `responseHeadersStart` | 响应头接收开始 |
| 13 | `responseHeaderEnd` | 响应头接收结束 |
| 14 | `responseBodyStart` | 响应体接收开始 |
| 15 | `responseBodyEnd` | 响应体接收结束 |

> ⏱ **时间计算示例**：
> - DNS 耗时 = `dnsEnd - dnsStart`
> - TCP 连接耗时 = `connectionAcquired - connectStart`
> - SSL 握手耗时 = `secureConnectEnd - secureConnectStart`
> - 总耗时 = `responseBodyEnd - callStart`

### 2. TCP Ping

测量 TCP 三次握手的延迟，适合测试特定端口的连通性。

#### 基本用法

```objectivec
// 创建请求
CLSTcpRequest *request = [[CLSTcpRequest alloc] init];
request.domain = @"cloud.tencent.com";
request.appKey = @"YOUR_APP_KEY";
request.port = 443;  // HTTPS 端口
request.maxTimes = 10;  // 探测 10 次
request.timeout = 5000;  // 超时 5 秒

// 执行探测
[[ClsNetworkDiagnosis sharedInstance] tcpPingv2:request complate:^(CLSResponse *response) {
    if (response.success) {
        NSDictionary *data = response.data;
        NSDictionary *netOrigin = data[@"netOrigin"];
        
        NSNumber *latencyMin = netOrigin[@"latency_min"];  // 最小延迟（毫秒）
        NSNumber *latencyMax = netOrigin[@"latency_max"];  // 最大延迟
        NSNumber *latencyAvg = netOrigin[@"latency_avg"];  // 平均延迟
        NSNumber *successCount = netOrigin[@"success_count"];  // 成功次数
        NSNumber *failureCount = netOrigin[@"failure_count"];  // 失败次数
        
        NSLog(@"TCP Ping 统计: 最小=%@ms, 平均=%@ms, 最大=%@ms, 成功=%@, 失败=%@", 
              latencyMin, latencyAvg, latencyMax, successCount, failureCount);
    } else {
        NSLog(@"❌ TCP Ping 失败: %@", response.errorMessage);
    }
}];
```

#### 常用端口

| 服务 | 端口 |
|------|------|
| HTTP | 80 |
| HTTPS | 443 |
| MySQL | 3306 |
| Redis | 6379 |
| MongoDB | 27017 |
| SSH | 22 |
| SMTP | 25 |
| DNS | 53 |

### 3. ICMP Ping

使用 ICMP 协议测量网络延迟和丢包率，适合网络质量评估。

#### 基本用法

```objectivec
// 创建请求
CLSPingRequest *request = [[CLSPingRequest alloc] init];
request.domain = @"cloud.tencent.com";
request.appKey = @"YOUR_APP_KEY";
request.maxTimes = 10;  // Ping 10 次
request.size = 64;  // 包大小 64 字节
request.interval = 200;  // 间隔 200ms
request.timeout = 10000;  // 超时 10 秒

// 执行探测
[[ClsNetworkDiagnosis sharedInstance] pingv2:request complate:^(CLSResponse *response) {
    if (response.success) {
        NSDictionary *data = response.data;
        NSDictionary *netOrigin = data[@"netOrigin"];
        
        NSNumber *latencyMin = netOrigin[@"latency_min"];  // 最小延迟（毫秒）
        NSNumber *latencyMax = netOrigin[@"latency_max"];  // 最大延迟
        NSNumber *latencyAvg = netOrigin[@"latency_avg"];  // 平均延迟
        NSNumber *latencyStddev = netOrigin[@"latency_stddev"];  // 标准差
        NSNumber *lossRate = netOrigin[@"loss_rate"];  // 丢包率（百分比）
        
        NSLog(@"Ping 统计: 延迟=%@/%@/%@ms, 抖动=%@ms, 丢包率=%@%%", 
              latencyMin, latencyAvg, latencyMax, latencyStddev, lossRate);
    } else {
        NSLog(@"❌ Ping 失败: %@", response.errorMessage);
    }
}];
```

#### IP 协议偏好控制（v3.0.0 新增）

```objectivec
CLSPingRequest *request = [[CLSPingRequest alloc] init];
request.domain = @"www.qq.com";
request.appKey = @"YOUR_APP_KEY";
request.maxTimes = 5;

// 设置 IP 协议偏好
request.prefer = -1;  // -1: 自动检测（默认）
                      //  0: IPv4 优先
                      //  1: IPv6 优先
                      //  2: 仅 IPv4
                      //  3: 仅 IPv6

[[ClsNetworkDiagnosis sharedInstance] pingv2:request complate:^(CLSResponse *response) {
    if (response.success) {
        NSDictionary *netOrigin = response.data[@"netOrigin"];
        NSString *hostIp = netOrigin[@"host_ip"];  // 实际使用的 IP 地址
        NSLog(@"使用 IP: %@", hostIp);
    }
}];
```

### 4. DNS 解析

查询域名的 DNS 记录（A 记录/AAAA 记录），支持自定义 DNS 服务器。

#### 基本用法

```objectivec
// 创建请求
CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
request.domain = @"cloud.tencent.com";
request.appKey = @"YOUR_APP_KEY";
request.timeout = 5000;  // 超时 5 秒

// 执行解析
[[ClsNetworkDiagnosis sharedInstance] dns:request complate:^(CLSResponse *response) {
    if (response.success) {
        NSDictionary *data = response.data;
        NSDictionary *netOrigin = data[@"netOrigin"];
        
        // 解析结果（JSON 数组）
        NSString *answerSection = netOrigin[@"answer_section"];
        NSLog(@"DNS 解析结果: %@", answerSection);
        
        /*
        示例输出：
        [
            {"name":"cloud.tencent.com","type":"A","ttl":300,"data":"203.205.158.53"},
            {"name":"cloud.tencent.com","type":"AAAA","ttl":300,"data":"2408:871a:2100:15::53"}
        ]
        */
    } else {
        NSLog(@"❌ DNS 解析失败: %@", response.errorMessage);
    }
}];
```

#### 自定义 DNS 服务器

```objectivec
CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
request.domain = @"cloud.tencent.com";
request.appKey = @"YOUR_APP_KEY";

// 使用公共 DNS 服务器
request.nameServer = @"8.8.8.8";  // Google DNS
// request.nameServer = @"1.1.1.1";  // Cloudflare DNS
// request.nameServer = @"119.29.29.29";  // DNSPod DNS

// IP 协议偏好
request.prefer = 0;  // 0: A 记录优先, 1: AAAA 记录优先

[[ClsNetworkDiagnosis sharedInstance] dns:request complate:^(CLSResponse *response) {
    // 处理结果
}];
```

### 5. MTR 路由跟踪

追踪数据包到目标主机的完整路径，包含每一跳的延迟和丢包率。

#### 基本用法

```objectivec
// 创建请求
CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
request.domain = @"cloud.tencent.com";
request.appKey = @"YOUR_APP_KEY";
request.maxTTL = 30;  // 最大跳数 30
request.protocol = @"icmp";  // 协议：icmp / udp
request.timeout = 60000;  // 超时 60 秒（路由跟踪耗时长）

// 执行探测
[[ClsNetworkDiagnosis sharedInstance] mtr:request complate:^(CLSResponse *response) {
    if (response.success) {
        NSDictionary *data = response.data;
        NSDictionary *netOrigin = data[@"netOrigin"];
        
        // 路径信息（JSON 数组）
        NSString *pathDetail = netOrigin[@"path_detail"];
        NSLog(@"路由路径: %@", pathDetail);
        
        /*
        示例输出：
        [
            {"hop":1,"ip":"192.168.1.1","latency":2.5,"latency_min":2.0,"latency_max":3.0,"loss":0,"responseNum":3},
            {"hop":2,"ip":"10.0.0.1","latency":10.2,"latency_min":8.5,"latency_max":12.0,"loss":0,"responseNum":3},
            {"hop":3,"ip":"203.205.158.1","latency":25.8,"latency_min":24.0,"latency_max":28.0,"loss":10,"responseNum":2},
            ...
        ]
        */
    } else {
        NSLog(@"❌ MTR 失败: %@", response.errorMessage);
    }
}];
```

#### 协议选择

| 协议 | 说明 | 适用场景 |
|------|------|---------|
| **ICMP** | 使用 ICMP Echo Request | 更准确，但可能被防火墙拦截 |
| **UDP** | 使用 UDP 包 | 穿透性好，适合被 ICMP 拦截的环境 |

### IP 协议偏好控制

v3.0.0 版本新增 `prefer` 参数，支持 IPv4/IPv6 协议偏好设置。

#### prefer 参数说明

| 值 | 说明 | 适用场景 |
|----|------|---------|
| **-1** | 自动检测（默认） | 由系统决定，优先使用双栈网络支持的协议 |
| **0** | IPv4 优先 | 双栈环境下优先使用 IPv4，IPv4 不可用时使用 IPv6 |
| **1** | IPv6 优先 | 双栈环境下优先使用 IPv6，IPv6 不可用时使用 IPv4 |
| **2** | IPv4 only | 仅使用 IPv4，IPv6 地址会被忽略 |
| **3** | IPv6 only | 仅使用 IPv6，IPv4 地址会被忽略 |

#### 使用示例

```objectivec
// 示例 1: 强制使用 IPv4（适用于纯 IPv4 环境）
CLSPingRequest *request = [[CLSPingRequest alloc] init];
request.domain = @"www.qq.com";
request.appKey = @"YOUR_APP_KEY";
request.prefer = 2;  // IPv4 only

[[ClsNetworkDiagnosis sharedInstance] pingv2:request complate:^(CLSResponse *response) {
    // 只会 Ping IPv4 地址：203.205.158.53
}];

// 示例 2: 仅查询 IPv6 DNS 记录
CLSDnsRequest *request = [[CLSDnsRequest alloc] init];
request.domain = @"www.qq.com";
request.appKey = @"YOUR_APP_KEY";
request.prefer = 3;  // IPv6 only - 仅返回 AAAA 记录

[[ClsNetworkDiagnosis sharedInstance] dns:request complate:^(CLSResponse *response) {
    // ANSWER-SECTION: [{"type": "AAAA", "data": "2408:871a:2100:15::53"}]
}];

// 示例 3: IPv6 优先（双栈环境）
CLSMtrRequest *request = [[CLSMtrRequest alloc] init];
request.domain = @"cloud.tencent.com";
request.appKey = @"YOUR_APP_KEY";
request.prefer = 1;  // IPv6 优先
request.protocol = @"icmp";

[[ClsNetworkDiagnosis sharedInstance] mtr:request complate:^(CLSResponse *response) {
    // 优先追踪 IPv6 路径，失败时自动降级到 IPv4
}];
```

#### 支持 prefer 参数的探测类型

| 探测类型 | 支持 prefer | 说明 |
|---------|------------|------|
| HTTP Ping | ❌ | 不支持（URL 已指定协议） |
| TCP Ping | ❌ | 不支持（直接指定 IP 或域名） |
| **ICMP Ping** | ✅ | 支持 |
| **DNS 解析** | ✅ | 支持 |
| **MTR 路由跟踪** | ✅ | 支持 |

---

## 📖 API 参考

### 日志上报 API

#### LogSender

| 方法 | 说明 |
|------|------|
| `+ (instancetype)sharedSender` | 获取单例 |
| `- (void)setConfig:(ClsLogSenderConfig *)config` | 设置配置 |
| `- (void)start` | 启动后台发送线程 |
| `- (void)stop` | 停止后台发送线程 |
| `- (void)updateToken:(NSString *)token` | 更新 STS 临时令牌 |

#### ClsLogStorage

| 方法 | 说明 |
|------|------|
| `+ (instancetype)sharedInstance` | 获取单例 |
| `- (void)writeLog:(Log *)logItem topicId:(NSString *)topicId completion:(void(^)(BOOL, NSError *))completion` | 写入日志 |
| `- (void)setMaxDatabaseSize:(uint64_t)maxSize` | 设置数据库上限 |

#### ClsLogSenderConfig

| 属性 | 类型 | 说明 |
|------|------|------|
| `endpoint` | NSString | CLS 接入点 |
| `accessKeyId` | NSString | 访问密钥 ID |
| `accessKey` | NSString | 访问密钥 Key |
| `token` | NSString | STS 临时令牌（可选） |
| `sendLogInterval` | uint64_t | 发送间隔（秒） |
| `maxMemorySize` | uint64_t | 数据库最大容量（字节） |

### 网络诊断 API

#### ClsNetworkDiagnosis

| 方法 | 说明 |
|------|------|
| `+ (instancetype)sharedInstance` | 获取单例 |
| `- (void)setupLogSenderWithConfig:topicId:` | 初始化（topicId 模式） |
| `- (void)setupLogSenderWithConfig:netToken:` | 初始化（netToken 模式） |
| `- (void)setUserEx:(NSDictionary *)userEx` | 设置全局扩展字段 |
| `- (void)httpingv2:complate:` | HTTP Ping 探测 |
| `- (void)tcpPingv2:complate:` | TCP Ping 探测 |
| `- (void)pingv2:complate:` | ICMP Ping 探测 |
| `- (void)dns:complate:` | DNS 解析探测 |
| `- (void)mtr:complate:` | MTR 路由跟踪探测 |

#### CLSRequest（基类）

| 属性 | 类型 | 说明 |
|------|------|------|
| `domain` | NSString | 探测域名/IP（必填） |
| `appKey` | NSString | 应用标识（必填） |
| `size` | int | 包大小（8-1024，默认 64） |
| `maxTimes` | int | 探测次数（1-100，默认 3） |
| `timeout` | int | 超时时间（毫秒，默认 10000） |
| `enableMultiplePortsDetect` | BOOL | 多网卡探测（默认 NO） |
| `pageName` | NSString | 页面名称（可选） |
| `detectEx` | NSDictionary | 扩展字段（可选） |
| `traceId` | NSString | 追踪 ID（可选） |

#### CLSHttpRequest

继承自 `CLSRequest`，新增：

| 属性 | 类型 | 说明 |
|------|------|------|
| `enableSSLVerification` | BOOL | SSL 证书验证（默认 YES） |

#### CLSTcpRequest

继承自 `CLSRequest`，新增：

| 属性 | 类型 | 说明 |
|------|------|------|
| `port` | NSInteger | 端口号（1-65535） |

#### CLSPingRequest

继承自 `CLSRequest`，新增：

| 属性 | 类型 | 说明 |
|------|------|------|
| `interval` | int | Ping 间隔（毫秒，默认 200） |
| `prefer` | int | IP 协议偏好（v3.0.0 新增） |

#### CLSDnsRequest

继承自 `CLSRequest`，新增：

| 属性 | 类型 | 说明 |
|------|------|------|
| `nameServer` | NSString | DNS 服务器（如 "8.8.8.8"） |
| `prefer` | int | IP 协议偏好（v3.0.0 新增） |

#### CLSMtrRequest

继承自 `CLSRequest`，新增：

| 属性 | 类型 | 说明 |
|------|------|------|
| `maxTTL` | int | 最大跳数（1-64，默认 30） |
| `protocol` | NSString | 协议（"icmp" / "udp"） |
| `prefer` | int | IP 协议偏好（v3.0.0 新增） |

#### CLSResponse

| 属性 | 类型 | 说明 |
|------|------|------|
| `success` | BOOL | 是否成功 |
| `errorMessage` | NSString | 错误信息 |
| `content` | NSString | 响应内容（JSON 字符串） |
| `data` | NSDictionary | 解析后的字典 |

---

## 💼 示例项目

### Objective-C Demo

**路径**: `/Xcode/TencentCloudLogDemo/`

#### 运行步骤

1. 安装依赖：
```bash
cd Xcode/TencentCloudLogDemo
pod install
```

2. 打开项目：
```bash
open TencentCloudLogDemo.xcworkspace
```

3. 修改配置：
   - 打开 `CLSLogUploadViewController.m`
   - 填入你的 `accessKeyId`、`accessKey`、`topicId`

4. 运行项目（⌘R）

#### 核心文件

| 文件 | 说明 |
|------|------|
| `CLSMainViewController.m` | 主页（功能入口） |
| `CLSLogUploadViewController.m` | 日志上报示例 |
| `CLSNetworkDetectViewController.m` | 网络诊断示例 |

### Swift Demo

**路径**: `/XcodeSwift/TencentCloudLogSwiftDemo/`

#### 运行步骤

1. 安装依赖：
```bash
cd XcodeSwift/TencentCloudLogSwiftDemo
pod install
```

2. 打开项目：
```bash
open TencentCloudLogSwiftDemo.xcworkspace
```

3. 修改配置：
   - 打开 `LogUploadViewController.swift`
   - 填入你的 `accessKeyId`、`accessKey`、`topicId`

4. 运行项目（⌘R）

#### 核心文件

| 文件 | 说明 |
|------|------|
| `MainViewController.swift` | 主页（功能入口） |
| `LogUploadViewController.swift` | 日志上报示例 |
| `NetworkDetectViewController.swift` | 网络诊断示例 |

### 测试套件

**路径**: `/Xcode/TencentCloudLogDemo/TencentCloudLogDemoTests/`

#### 测试覆盖

| 测试类 | 测试数量 | 说明 |
|--------|---------|------|
| `TencentcloudLogHttpping.m` | 8+ | HTTP Ping 测试 |
| `ZhiyanPingDetectionTests.m` | 10+ | ICMP Ping 测试 |
| `ZhiyanTcppingDetectionTests.m` | 8+ | TCP Ping 测试 |
| `ZhiyanDnsDetectionTests.m` | 12+ | DNS 解析测试 |
| `ZhiyanMtrDetectionTests.m` | 9+ | MTR 路由跟踪测试 |
| `CLSWiFiOnlyDetectionTests.m` | 5+ | 多网卡探测测试 |

#### 运行测试

```bash
# 命令行运行
xcodebuild test \
  -workspace TencentCloudLogDemo.xcworkspace \
  -scheme TencentCloudLogDemo \
  -destination 'platform=iOS Simulator,name=iPhone 14'

# 或在 Xcode 中按 ⌘U
```

---

## ❓ 常见问题

### 1. 桥接头文件未找到

**问题**：Swift 项目提示找不到头文件

**解决方案**：
1. 检查桥接头文件路径是否正确
2. 在 **Build Settings** 中搜索 `Bridging`
3. 设置 **Objective-C Bridging Header** 为正确路径

### 2. 日志未上报

**问题**：日志写入成功但未在 CLS 控制台看到

**排查步骤**：
1. 检查 `endpoint`、`accessKeyId`、`accessKey`、`topicId` 是否正确
2. 检查网络是否可达：`[[LogSender sharedSender] isNetworkAvailable]`
3. 查看本地数据库是否有数据：SQLite 文件在 `/Library/Caches/` 目录

### 3. 网络诊断无结果

**问题**：探测返回 `success = NO`

**排查步骤**：
1. 检查 `appKey` 是否正确填写
2. 检查 `domain` 格式是否正确（HTTP Ping 需要完整 URL）
3. 检查网络权限：确保 Info.plist 中有网络权限配置
4. 查看 `errorMessage` 详细错误信息

### 4. 多网卡探测失败

**问题**：`enableMultiplePortsDetect = YES` 但只有一个网卡结果

**原因**：
- 设备未同时连接 WiFi 和蜂窝网络
- iOS 模拟器不支持蜂窝网络

**解决方案**：
- 使用真机测试
- 同时开启 WiFi 和蜂窝数据

### 5. IPv6 探测失败

**问题**：`prefer = 3`（IPv6 only）时探测失败

**原因**：
- 目标服务器不支持 IPv6
- 当前网络环境不支持 IPv6

**解决方案**：
- 使用 `prefer = 1`（IPv6 优先）替代 `prefer = 3`
- 测试时使用支持 IPv6 的域名（如 `www.qq.com`）

### 6. CocoaPods 安装失败

**问题**：`pod install` 报错

**解决方案**：
```bash
# 更新 CocoaPods 仓库
pod repo update

# 清理缓存
pod cache clean --all

# 重新安装
pod install --repo-update
```

---

## 📊 性能指标

### 日志上报性能

| 指标 | 数值 | 说明 |
|------|------|------|
| **单次写入耗时** | < 1ms | 异步写入，不阻塞主线程 |
| **批量发送间隔** | 5 秒 | 可配置 1-60 秒 |
| **单次批量上限** | 100 条 | 避免单次请求过大 |
| **单日志大小上限** | 512KB | 超过会被拆分 |
| **聚合包大小上限** | 5MB | 单次请求最大 5MB |
| **压缩率** | 平均 70% | LZ4 压缩算法 |
| **数据库默认上限** | 32MB | 可配置，FIFO 策略 |

### 网络诊断性能

| 探测类型 | 平均耗时 | 推荐次数 | 说明 |
|---------|---------|---------|------|
| **HTTP Ping** | 300-500ms | 3 次 | 完整 HTTP 生命周期 |
| **TCP Ping** | 100-200ms | 5 次 | 仅 TCP 三次握手 |
| **ICMP Ping** | 50-100ms | 10 次 | 最快的探测方式 |
| **DNS 解析** | 50-100ms | 1 次 | 域名解析 |
| **MTR 路由** | 5-15秒 | 1 次 | 最大跳数 30 |

### 资源占用

| 资源 | 数值 |
|------|------|
| **内存占用** | < 5MB（峰值 < 10MB） |
| **CPU 占用** | < 1%（后台线程） |
| **磁盘占用** | 默认 32MB（可配置） |
| **网络流量** | 取决于日志量，平均压缩 70% |

---

## 💡 最佳实践

### 1. 日志上报最佳实践

#### ✅ 推荐做法

```objectivec
// 1. 在 AppDelegate 中初始化一次
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou.cls.tencentcs.com"
                                                         accessKeyId:@"YOUR_ACCESS_KEY_ID"
                                                           accessKey:@"YOUR_ACCESS_KEY"];
    [[LogSender sharedSender] setConfig:config];
    [[LogSender sharedSender] start];
    return YES;
}

// 2. 使用临时密钥（生产环境）
- (void)refreshSTSToken {
    [self.authService getTemporaryCredentials:^(NSDictionary *credentials) {
        ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou.cls.tencentcs.com"
                                                             accessKeyId:credentials[@"tmpSecretId"]
                                                               accessKey:credentials[@"tmpSecretKey"]];
        config.token = credentials[@"sessionToken"];
        [[LogSender sharedSender] setConfig:config];
    }];
}
```

#### ❌ 错误做法

```objectivec
// 错误 1: 重复初始化
- (void)someMethod {
    LogSender *sender = [LogSender sharedSender];
    [sender start];  // ❌ 不要在非 AppDelegate 中调用 start
}

// 错误 2: 永久密钥硬编码
ClsLogSenderConfig *config = [[ClsLogSenderConfig alloc] init];
config.accessKeyId = @"AKIDxxxxxxx";  // ❌ 不要硬编码永久密钥
config.accessKey = @"xxxxxxxx";

// 错误 3: 同步写入日志
for (int i = 0; i < 10000; i++) {
    Log *log = [self createLog];
    [[ClsLogStorage sharedInstance] writeLog:log topicId:@"xxx" completion:^(BOOL success, NSError *error) {
        while (!success) {  // ❌ 不要阻塞等待
            // 等待写入成功
        }
    }];
}
```

### 2. 网络诊断最佳实践

#### ✅ 推荐做法

```objectivec
// 1. 初始化时提前设置全局扩展字段
- (void)setupNetworkDiagnosis {
    ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"ap-guangzhou-open.cls.tencentcs.com"
                                                         accessKeyId:@"YOUR_ACCESS_KEY_ID"
                                                           accessKey:@"YOUR_ACCESS_KEY"];
    [[ClsNetworkDiagnosis sharedInstance] setupLogSenderWithConfig:config topicId:@"YOUR_TOPIC_ID"];
    
    // 设置全局扩展字段（所有探测共享）
    [[ClsNetworkDiagnosis sharedInstance] setUserEx:@{
        @"app_version": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
        @"device_id": [self getDeviceId],
        @"user_id": [self getCurrentUserId]
    }];
}

// 2. 根据场景选择合适的探测方式
- (void)diagnoseNetworkIssue {
    // 场景 1: 接口调用失败，排查网络问题
    CLSHttpRequest *httpRequest = [[CLSHttpRequest alloc] init];
    httpRequest.domain = @"https://api.example.com/health";
    httpRequest.appKey = @"YOUR_APP_KEY";
    httpRequest.detectEx = @{@"api_name": @"/health"};
    [[ClsNetworkDiagnosis sharedInstance] httpingv2:httpRequest complate:^(CLSResponse *response) {
        // 分析 HTTP 生命周期各阶段耗时
    }];
    
    // 场景 2: 网络质量差，评估丢包率和延迟
    CLSPingRequest *pingRequest = [[CLSPingRequest alloc] init];
    pingRequest.domain = @"cloud.tencent.com";
    pingRequest.appKey = @"YOUR_APP_KEY";
    pingRequest.maxTimes = 10;  // 10 次 Ping 获得准确统计
    pingRequest.enableMultiplePortsDetect = YES;  // 对比 WiFi 和蜂窝网络
    [[ClsNetworkDiagnosis sharedInstance] pingv2:pingRequest complate:^(CLSResponse *response) {
        // 查看 loss_rate（丢包率）和 latency_avg（平均延迟）
    }];
    
    // 场景 3: 路由异常，追踪中间链路
    CLSMtrRequest *mtrRequest = [[CLSMtrRequest alloc] init];
    mtrRequest.domain = @"cloud.tencent.com";
    mtrRequest.appKey = @"YOUR_APP_KEY";
    mtrRequest.protocol = @"icmp";
    [[ClsNetworkDiagnosis sharedInstance] mtr:mtrRequest complate:^(CLSResponse *response) {
        // 分析路径中哪一跳出现高延迟或丢包
    }];
}

// 3. 处理探测结果
- (void)handleDetectResponse:(CLSResponse *)response {
    if (response.success) {
        // 解析结果
        NSDictionary *data = response.data;
        NSDictionary *netOrigin = data[@"netOrigin"];
        
        // 上报到自定义分析平台
        [self.analyticsService reportNetworkMetrics:netOrigin];
        
        // 触发告警（如丢包率 > 10%）
        if ([netOrigin[@"loss_rate"] doubleValue] > 10.0) {
            [self.alertService triggerNetworkQualityAlert];
        }
    } else {
        NSLog(@"探测失败: %@", response.errorMessage);
    }
}
```

#### ❌ 错误做法

```objectivec
// 错误 1: 过于频繁的探测
for (int i = 0; i < 100; i++) {
    [[ClsNetworkDiagnosis sharedInstance] pingv2:request complate:^(CLSResponse *response) {
        // ❌ 短时间内大量探测会被限流
    }];
}

// 错误 2: HTTP Ping 使用错误的 URL 格式
CLSHttpRequest *request = [[CLSHttpRequest alloc] init];
request.domain = @"cloud.tencent.com";  // ❌ 应该是完整 URL: https://cloud.tencent.com

// 错误 3: 阻塞主线程等待结果
[[ClsNetworkDiagnosis sharedInstance] httpingv2:request complate:^(CLSResponse *response) {
    dispatch_semaphore_signal(semaphore);
}];
dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);  // ❌ 不要阻塞主线程
```

### 3. 性能优化建议

#### 日志上报优化

```objectivec
// 1. 调整发送间隔（根据业务需求）
ClsLogSenderConfig *config = [[ClsLogSenderConfig alloc] init];
config.sendLogInterval = 3;  // 高频场景：3 秒
// config.sendLogInterval = 10;  // 低频场景：10 秒

// 2. 调整数据库容量（根据设备存储）
config.maxMemorySize = 16 * 1024 * 1024;  // 弱网环境：16MB
// config.maxMemorySize = 64 * 1024 * 1024;  // WiFi 环境：64MB

// 3. 批量写入日志（避免单条写入）
NSMutableArray *logs = [NSMutableArray array];
for (int i = 0; i < 100; i++) {
    Log *log = [self createLog:i];
    [logs addObject:log];
}

// 批量写入（使用 dispatch_group）
dispatch_group_t group = dispatch_group_create();
for (Log *log in logs) {
    dispatch_group_enter(group);
    [[ClsLogStorage sharedInstance] writeLog:log topicId:@"YOUR_TOPIC_ID" completion:^(BOOL success, NSError *error) {
        dispatch_group_leave(group);
    }];
}
dispatch_group_notify(group, dispatch_get_main_queue(), ^{
    NSLog(@"✅ 批量写入完成");
});
```

#### 网络诊断优化

```objectivec
// 1. 合理设置探测次数（避免过度探测）
CLSPingRequest *request = [[CLSPingRequest alloc] init];
request.maxTimes = 5;  // 5 次足够获得统计结果
// request.maxTimes = 3;  // 快速探测：3 次

// 2. 使用多网卡探测（移动网络场景）
request.enableMultiplePortsDetect = YES;  // 对比 WiFi 和蜂窝网络质量

// 3. 设置合理的超时时间
request.timeout = 10000;  // 10 秒（考虑弱网环境）
// request.timeout = 5000;  // 5 秒（WiFi 环境）

// 4. 使用 traceId 关联多个探测
NSString *traceId = [[NSUUID UUID] UUIDString];

CLSHttpRequest *httpRequest = [[CLSHttpRequest alloc] init];
httpRequest.traceId = traceId;
httpRequest.domain = @"https://api.example.com";

CLSPingRequest *pingRequest = [[CLSPingRequest alloc] init];
pingRequest.traceId = traceId;  // 同一个 traceId
pingRequest.domain = @"api.example.com";

// 可以在 CLS 控制台通过 traceId 关联分析
```

---

## 📝 更新日志

### v3.0.0

#### 🆕 新增功能
- ✅ 新增 IP 协议偏好控制（`prefer` 参数），支持 IPv4/IPv6 优先、仅 IPv4/IPv6、自动检测
- ✅ 支持 `topicId` 和 `netToken` 两种初始化方式
- ✅ netToken 自动提前解析并缓存，性能提升 99%+
- ✅ 新增 14 个测试用例（IPv4/IPv6 偏好测试 + topicId 模式测试）

#### 🐛 修复
- 🔧 修复多网卡探测时网卡绑定失败的问题
- 🔧 优化 netToken 解析性能

### v2.0.0 (2024-12-15)

#### 🆕 新增功能
- ✅ 新增网络诊断模块（NetWorkDiagnosis）
- ✅ 支持 5 种探测方式：HTTP Ping、TCP Ping、ICMP Ping、DNS 解析、MTR 路由跟踪
- ✅ 支持多网卡并发探测
- ✅ 完整的 OpenTelemetry Span 数据格式

#### 🚀 优化
- 🚀 优化日志上报性能，支持 LZ4 压缩
- 🚀 优化数据库管理，支持 VACUUM 压缩

### v1.0.0 (2024-06-01)

#### 🆕 新增功能
- ✅ 初始版本发布
- ✅ 支持日志上报功能
- ✅ 支持 SQLite 本地缓存
- ✅ 支持腾讯云 CAM 签名认证

---

## 📞 技术支持

### 官方文档

- [腾讯云 CLS 官网](https://cloud.tencent.com/product/cls)
- [CLS 文档中心](https://cloud.tencent.com/document/product/614)
- [iOS SDK 文档](https://cloud.tencent.com/document/product/614/67157)

### GitHub

- [GitHub 仓库](https://github.com/TencentCloud/tencentcloud-cls-sdk-ios)
- [提交 Issue](https://github.com/TencentCloud/tencentcloud-cls-sdk-ios/issues)
- [Pull Request](https://github.com/TencentCloud/tencentcloud-cls-sdk-ios/pulls)

### CocoaPods

- [CocoaPods 页面](https://cocoapods.org/pods/TencentCloudLogProducer)

### 联系我们

- **邮箱**: herrylv@tencent.com
- **技术支持**: [提交工单](https://console.cloud.tencent.com/workorder)

---

## 📄 许可证

本项目采用 [MIT 许可证](LICENSE)。

---

## 🙏 致谢

感谢以下开源项目：

- [Protobuf](https://github.com/protocolbuffers/protobuf) - 高效的数据序列化
- [FMDB](https://github.com/ccgus/fmdb) - SQLite 封装
- [Reachability](https://github.com/tonymillion/Reachability) - 网络可达性检测

---

<div align="center">
  <p>如有问题或建议，欢迎提交 <a href="https://github.com/TencentCloud/tencentcloud-cls-sdk-ios/issues">Issue</a> 或 <a href="https://github.com/TencentCloud/tencentcloud-cls-sdk-ios/pulls">Pull Request</a></p>
  <p>⭐ 如果觉得有帮助，欢迎 Star 支持我们！</p>
</div>
