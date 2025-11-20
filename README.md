# cls log service ios sdk

## 功能特点

* 异步
    * 异步写入，客户端线程无阻塞
* 聚合&压缩 上传
    * 支持按超时时间、日志数、日志size聚合数据发送
    * 支持lz4压缩
* 缓存
    * 支持缓存上限可设置
    * 超过上限后日志写入失败



- 核心上报架构

![ios核心架构图](ios_sdk.jpg)

## oc 配置说明

### import

```
#import "TencentCloudLogProducer/ClsLogSender.h"
#import "TencentCloudLogProducer/CLSLogStorage.h"
```

### Podfile

```objective-c
pod 'TencentCloudLogProducer/Core', '2.0.0'
```

### 配置

| 参数                           | 说明                                                             |                                                                                                    取值                                                                                                     |
|------------------------------|----------------------------------------------------------------|:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------:|
| topic                        | 日志主题 ID                                                        |                                                                         可在控制台获取https://console.cloud.tencent.com/cls/logset/desc                                                                          |
| accessKeyId                  | 访问密钥ID                                                         | 密钥信息获取请前往[密钥获取](https://console.cloud.tencent.com/cam/capi)。并请确保密钥关联的账号具有相应的[SDK上传日志权限](https://cloud.tencent.com/document/product/614/68374#.E4.BD.BF.E7.94.A8-api-.E4.B8.8A.E4.BC.A0.E6.95.B0.E6.8D.AE) |
| accessKey                    | 访问密钥Key                                                        | 密钥信息获取请前往[密钥获取](https://console.cloud.tencent.com/cam/capi)。并请确保密钥关联的账号具有相应的[SDK上传日志权限](https://cloud.tencent.com/document/product/614/68374#.E4.BD.BF.E7.94.A8-api-.E4.B8.8A.E4.BC.A0.E6.95.B0.E6.8D.AE) |
| endpoint                     | 地域信息                                                           |                                                                        参考官方文档：https://cloud.tencent.com/document/product/614/18940                                                                        |
| token                        | 临时密钥                                                           |                                                                                               若使用临时密钥需要设置该值                                                                                               |
| sendLogInterval           | 日志的发送逗留时间，默认5S                      |                                                                                                  整数，单位秒                                                                                                   |
| maxMemorySize               | sdk内存的上限，默认32M                                                 |                                                                                                  整数，单位字节                                                                                                  |
### 使用demo

```objective-c
#import "TencentCloudLogProducer/ClsLogSender.h"
#import "TencentCloudLogProducer/CLSLogStorage.h"

#启动sdk
ClsLogSenderConfig *config = [ClsLogSenderConfig configWithEndpoint:@"endpoint"
                                                  accessKeyId:@"accessKeyId"
                                                    accessKey:@"accessKey"];
_sender = [LogSender sharedSender];
[_sender setConfig:config];
[_sender start];

#写日志
Log_Content *content = [Log_Content message];
content.key = @"key";
content.value = @"value";

Log *logItem = [Log message];
     [logItem.contentsArray addObject:content];
     logItem.time = [timestamp longLongValue];

[[ClsLogStorage sharedInstance] writeLog:logItem
                                 topicId:@"topicid"
                               completion:^(BOOL success, NSError *error) {
    if (success) {
        NSLog(@"日志写入成功（第 %d 条），等待发送", i + 1);
    } else {
        NSLog(@"日志写入失败（第 %d 条），error: %@", i + 1, error);
    }
}];
```

## swift配置说明

### 桥接必要的头文件

```
#import "TencentCloudLogProducer/ClsLogSender.h"
#import "TencentCloudLogProducer/ClsLogModel.h"
#import "TencentCloudLogProducer/CLSLogStorage.h"
#import "TencentCloudLogProducer/ClsLogs.pbobjc.h"
```

### Podfile

```swift
pod 'TencentCloudLogProducer/Core', '2.0.0'
import TencentCloudLogProducer
```

### 配置

| 参数                           | 说明                                                             |                                                                                                    取值                                                                                                     |
|------------------------------|----------------------------------------------------------------|:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------:|
| topic                        | 日志主题 ID                                                        |                                                                         可在控制台获取https://console.cloud.tencent.com/cls/logset/desc                                                                          |
| accessKeyId                  | 访问密钥ID                                                         | 密钥信息获取请前往[密钥获取](https://console.cloud.tencent.com/cam/capi)。并请确保密钥关联的账号具有相应的[SDK上传日志权限](https://cloud.tencent.com/document/product/614/68374#.E4.BD.BF.E7.94.A8-api-.E4.B8.8A.E4.BC.A0.E6.95.B0.E6.8D.AE) |
| accessKey                    | 访问密钥Key                                                        | 密钥信息获取请前往[密钥获取](https://console.cloud.tencent.com/cam/capi)。并请确保密钥关联的账号具有相应的[SDK上传日志权限](https://cloud.tencent.com/document/product/614/68374#.E4.BD.BF.E7.94.A8-api-.E4.B8.8A.E4.BC.A0.E6.95.B0.E6.8D.AE) |
| endpoint                     | 地域信息                                                           |                                                                        参考官方文档：https://cloud.tencent.com/document/product/614/18940                                                                        |
| token                        | 临时密钥                                                           |                                                                                               若使用临时密钥需要设置该值                                                                                               |
| sendLogInterval           | 日志的发送逗留时间，默认5S                      |                                                                                                  整数，单位秒                                                                                                   |
| maxMemorySize               | sdk内存的上限，默认32M                                                 |                                                                                                  整数，单位字节                                                                                                  |

### 使用demo

```
import TencentCloudLogProducer
//初始化sdk
let config = ClsLogSenderConfig(
   endpoint: "endpoint" ?? "",
   accessKeyId: "accessKeyId" ?? "",
   accessKey: "accessKey" ?? ""
)
sender = LogSender.shared()
sender.setConfig(config)
sender.start()

#发送数据
let content = Log_Content()
content.key = "key"
content.value = value

let logItem = Log()
logItem.contentsArray.add(content)
logItem.time = Int64(timestamp)!

// 写入日志
ClsLogStorage.sharedInstance().write(logItem, topicId: "topicid")
 { success, error in
    if success {
        print("日志写入成功（第 \(i + 1) 条），等待发送")
    } else {
        print("日志写入失败（第 \(i + 1) 条），error: \(error.debugDescription)")
    }
}
```

## 网络探测

### import

```objective-c
#import "ClsNetworkDiagnosis.h"
#import "ClsAdapter.h"
#import "ClsNetDiag.h"
```

- ClsNetworkDiagnosis.h 网络探测核心功能入口文件
- ClsAdapter.h 插件管理器
- ClsNetDiag.h 网络探测output输出文件，用户可自定义实现write方法

### Podfile

```objective-c
pod 'TencentCloudLogProducer/NetWorkDiagnosis'
```

### 配置说明

| 参数            | 说明                                                         |
| --------------- | ------------------------------------------------------------ |
| appVersion      | App版本号                                                    |
| appName         | App名称                                                      |
| endpoint        | 地域信息。参考官方文档：https://cloud.tencent.com/document/product/614/18940 |
| accessKeyId     | 密钥id。密钥信息获取请前往[密钥获取](https://console.cloud.tencent.com/cam/capi)。并请确保密钥关联的账号具有相应的[SDK上传日志权限](https://cloud.tencent.com/document/product/614/68374#.E4.BD.BF.E7.94.A8-api-.E4.B8.8A.E4.BC.A0.E6.95.B0.E6.8D.AE) |
| accessKeySecret | 密钥key。密钥信息获取请前往[密钥获取](https://console.cloud.tencent.com/cam/capi)。并请确保密钥关联的账号具有相应的[SDK上传日志权限](https://cloud.tencent.com/document/product/614/68374#.E4.BD.BF.E7.94.A8-api-.E4.B8.8A.E4.BC.A0.E6.95.B0.E6.8D.AE) |
| topicId         | 主题信息。可在控制台获取https://console.cloud.tencent.com/cls/logset/desc |
| pluginAppId     | 插件appid                                                    |
| channel         | 自定义参数，App渠道标识。                                    |
| channelName     | 自定义参数，App渠道名称。                                    |
| userNick        | 自定义参数，用户昵称。                                       |
| longLoginNick   | 自定义参数，用户昵称，最后一次登录的用户昵称                 |
| userId          | 自定义参数，用户ID。                                         |
| longLoginUserId | 自定义参数，用户ID，最后一次登录的用户ID。                   |
| loginType       | 自定义参数，用户登录类型。                                   |
| ext             | 用于添加业务参数，键值对形式。                               |

### 使用demo

#### 插件初始化

```
ClsConfig *config = [[ClsConfig alloc] init];
[config setDebuggable:YES];
[config setEndpoint: @"ap-guangzhou.cls.tencentcs.com"];
[config setAccessKeyId: @""];
[config setAccessKeySecret: @""];
[config setTopicId:@""];
[config setPluginAppId: @"your pluginid"];

    // 自定义参数
[config setUserId:@"user1"];
[config setChannel:@"channel1"];
[config addCustomWithKey:@"customKey" andValue:@"testValue"];
    
ClsAdapter *clsAdapter = [ClsAdapter sharedInstance];
[clsAdapter addPlugin:[[CLSNetworkDiagnosisPlugin alloc] init]];
[clsAdapter initWithCLSConfig:config];
```

#### ping方法探测

- 方法1

```objective-c
/**
* @param host   目标 host，如 cloud.tencent.com
* @param size   数据包大小
* @param output   输出 callback
* @param callback 回调 callback
*/
- (void)ping:(NSString*)host size:(NSUInteger)size output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete;
```

- 方法2

```objective-c
/**
* @param host   目标 host，如 cloud.tencent.com
* @param size   数据包大小
* @param task_timeout 任务超时。毫秒单位
* @param output   输出 callback
* @param callback 回调 callback
* @param count 探测次数
*/
- (void)ping:(NSString*)host size:(NSUInteger)size task_timeout:(NSUInteger)task_timeout output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete count:(NSInteger)count;
```
- 方法3

```objective-c
/**
* @param host   目标 host，如 cloud.tencent.com
* @param size   数据包大小
* @param output   输出 callback
* @param callback 回调 callback
* @param customFiled 自定义字段
*/
- (void)ping:(NSString*)host size:(NSUInteger)size output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete customFiled:(NSMutableDictionary*) customFiled;
```

#### tcpping探测方法

- 方法1

```objective-c
/**
* @param host   目标 host，如：cloud.tencent.com
* @param output   输出 callback                
* @param callback 回调 callback
*/
- (void)tcpPing:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete;
```

- 方法2

```objective-c
/**
* @param host     目标 host，如：cloud.tencent.com
* @param port     端口号
* @param task_timeout 任务超时。毫秒单位
* @param count.   探测次数
* @param output   输出 callback                
* @param callback 回调 callback
*/
- (void)tcpPing:(NSString*)host port:(NSUInteger)port task_timeout:(NSUInteger)task_timeout count:(NSInteger)count output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete;
```
- 方法3

```objective-c
/**
* @param host   目标 host，如：cloud.tencent.com
* @param output   输出 callback                
* @param callback 回调 callback
* @param customFiled 自定义字段
*/
- (void)tcpPing:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete customFiled:(NSMutableDictionary*) customFiled;
```

#### traceroute方法

- 方法1

```objective-c
/**
* @param host 目标 host，如：cloud.tencent.com
* @param output 输出 callback
* @param callback 回调 callback
*/
- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete;
```



- 方法2

```objective-c
/**
* @param host 目标 host，如：cloud.tencent.com
* @param maxTtl 最大存活跳数
* @param countPerRoute
* @param output   输出 callback
* @param callback 回调 callback
*/
- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete maxTtl:(NSInteger)maxTtl;
```
- 方法3

```objective-c
/**
* @param host 目标 host，如：cloud.tencent.com
* @param output 输出 callback
* @param callback 回调 callback
* @param customFiled 自定义字段
*/
- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete customFiled:(NSMutableDictionary*) customFiled;
```

#### httping方法

- 方法1
```objective-c
/**
* @param url 如：https://ap-guangzhou.cls.tencentcs.com/ping
* @param output   输出 callback
* @param callback 回调 callback
*/
- (void) httping:(NSString*)url output:(id<CLSOutputDelegate>)output complate:(CLSHttpCompleteHandler)complate;
```
- 方法2
```objective-c
/**
* @param url 如：https://ap-guangzhou.cls.tencentcs.com/ping
* @param output   输出 callback
* @param callback 回调 callback
* @param customFiled 自定义字段
*/
- (void) httping:(NSString*)url output:(id<CLSOutputDelegate>)output complate:(CLSHttpCompleteHandler)complate customFiled:(NSMutableDictionary*) customFiled;
```




