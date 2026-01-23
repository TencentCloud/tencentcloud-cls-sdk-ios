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

### Objective-C

#### import

```objective-c
#import "ClsNetworkDiagnosis.h"
#import "ClsAdapter.h"
#import "ClsNetDiag.h"
```

- ClsNetworkDiagnosis.h 网络探测核心功能入口文件
- ClsAdapter.h 插件管理器
- ClsNetDiag.h 网络探测output输出文件，用户可自定义实现write方法

#### Podfile

```objective-c
pod 'TencentCloudLogProducer/NetWorkDiagnosis'
```

#### 配置说明

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

#### 使用demo

##### 插件初始化

```objective-c
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

##### ping方法探测

###### 方法1

```objective-c
/**
* @param host   目标 host，如 cloud.tencent.com
* @param size   数据包大小
* @param output   输出 callback
* @param callback 回调 callback
*/
- (void)ping:(NSString*)host size:(NSUInteger)size output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete;
```

###### 方法2

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
###### 方法3

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

##### tcpping探测方法

###### 方法1

```objective-c
/**
* @param host   目标 host，如：cloud.tencent.com
* @param output   输出 callback                
* @param callback 回调 callback
*/
- (void)tcpPing:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete;
```

###### 方法2

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
###### 方法3

```objective-c
/**
* @param host   目标 host，如：cloud.tencent.com
* @param output   输出 callback                
* @param callback 回调 callback
* @param customFiled 自定义字段
*/
- (void)tcpPing:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete customFiled:(NSMutableDictionary*) customFiled;
```

##### traceroute方法

###### 方法1

```objective-c
/**
* @param host 目标 host，如：cloud.tencent.com
* @param output 输出 callback
* @param callback 回调 callback
*/
- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete;
```



###### 方法2

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
###### 方法3

```objective-c
/**
* @param host 目标 host，如：cloud.tencent.com
* @param output 输出 callback
* @param callback 回调 callback
* @param customFiled 自定义字段
*/
- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete customFiled:(NSMutableDictionary*) customFiled;
```

##### httping方法

###### 方法1
```objective-c
/**
* @param url 如：https://ap-guangzhou.cls.tencentcs.com/ping
* @param output   输出 callback
* @param callback 回调 callback
*/
- (void) httping:(NSString*)url output:(id<CLSOutputDelegate>)output complate:(CLSHttpCompleteHandler)complate;
```
###### 方法2
```objective-c
/**
* @param url 如：https://ap-guangzhou.cls.tencentcs.com/ping
* @param output   输出 callback
* @param callback 回调 callback
* @param customFiled 自定义字段
*/
- (void) httping:(NSString*)url output:(id<CLSOutputDelegate>)output complate:(CLSHttpCompleteHandler)complate customFiled:(NSMutableDictionary*) customFiled;
```

---

### Swift

#### 桥接头文件配置

在 Swift 项目中使用网络探测功能，需要在 Bridging Header 中导入以下头文件：

```swift
// TencentCloudLogSwiftDemo-Bridging-Header.h

// 导入日志上传核心模块
#import "TencentCloudLogProducer/ClsLogSender.h"
#import "TencentCloudLogProducer/ClsLogModel.h"
#import "TencentCloudLogProducer/CLSLogStorage.h"
#import "TencentCloudLogProducer/ClsLogs.pbobjc.h"

// 导入网络探测模块
#import "ClsNetworkDiagnosis.h"
#import "ClsAdapter.h"
#import "ClsNetDiag.h"
```

#### Podfile

```ruby
pod 'TencentCloudLogProducer/NetWorkDiagnosis'
```

#### 配置说明

| 参数            | 说明                                                         |
| --------------- | ------------------------------------------------------------ |
| endpoint        | 地域信息。参考官方文档：https://cloud.tencent.com/document/product/614/18940 |
| accessKeyId     | 密钥id。密钥信息获取请前往[密钥获取](https://console.cloud.tencent.com/cam/capi) |
| accessKeySecret | 密钥key。密钥信息获取请前往[密钥获取](https://console.cloud.tencent.com/cam/capi) |
| topicId         | 主题信息。可在控制台获取https://console.cloud.tencent.com/cls/logset/desc |
| pluginAppId     | 插件appid                                                    |
| userId          | 自定义参数，用户ID                                           |
| channel         | 自定义参数，App渠道标识                                      |

#### 使用demo

##### 1. 插件初始化

```swift
import UIKit
import TencentCloudLogProducer

class NetworkDiagnosisViewController: UIViewController {
    private var networkDiagnosis: ClsNetworkDiagnosis?
    private var diagOutput: ClsDiagOutput?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initializeNetworkDiagnosis()
    }
    
    private func initializeNetworkDiagnosis() {
        // 创建配置
        let config = ClsConfig()
        config.setDebuggable(true)
        config.setEndpoint("ap-guangzhou.cls.tencentcs.com")
        config.setAccessKeyId("your_access_key_id")
        config.setAccessKeySecret("your_access_key_secret")
        config.setTopicId("your_topic_id")
        config.setPluginAppId("your_plugin_id")
        
        // 自定义参数
        config.setUserId("swift_user_001")
        config.setChannel("swift_demo_channel")
        config.addCustom(withKey: "platform", andValue: "iOS")
        config.addCustom(withKey: "language", andValue: "Swift")
        
        // 初始化插件
        let clsAdapter = ClsAdapter.sharedInstance()
        clsAdapter?.addPlugin(CLSNetworkDiagnosisPlugin())
        clsAdapter?.initWithCLS(config)
        
        // 获取网络探测实例
        networkDiagnosis = ClsNetworkDiagnosis.getInstance()
        
        // 创建输出处理器
        diagOutput = ClsDiagOutput()
    }
}

// 自定义输出处理器
class ClsDiagOutput: NSObject, CLSOutputDelegate {
    func write(_ jsonString: String) {
        print("📤 网络探测输出: \(jsonString)")
    }
}
```

##### 2. Ping 探测

```swift
// 方法1：基础探测
networkDiagnosis?.ping(
    "cloud.tencent.com",
    size: 64,
    output: diagOutput,
    complete: { result in
        guard let result = result else { return }
        print("Ping 结果: IP=\(result.ip ?? "N/A"), 平均延迟=\(result.avgTime)ms")
    }
)

// 方法2：指定探测次数和超时时间
networkDiagnosis?.ping(
    "cloud.tencent.com",
    size: 64,
    task_timeout: 5000,    // 超时时间（毫秒）
    output: diagOutput,
    complete: { result in
        guard let result = result else { return }
        print("✅ 探测完成:")
        print("  总包数: \(result.count)")
        print("  成功数: \(result.count - result.loss)")
        print("  丢包数: \(result.loss)")
        print("  最小延迟: \(result.minTime)ms")
        print("  最大延迟: \(result.maxTime)ms")
        print("  平均延迟: \(result.avgTime)ms")
        print("  标准差: \(result.stddev)ms")
    },
    count: 5               // 探测次数
)

// 方法3：带自定义字段
var customFields = NSMutableDictionary()
customFields["scene"] = "login_test"
customFields["user_level"] = "vip"

networkDiagnosis?.ping(
    "cloud.tencent.com",
    size: 64,
    output: diagOutput,
    complete: { result in
        // 处理结果
    },
    customFiled: customFields
)
```

##### 3. TCPing 探测

```swift
// 方法1：基础探测（默认80端口）
networkDiagnosis?.tcpPing(
    "cloud.tencent.com",
    output: diagOutput,
    complete: { result in
        guard let result = result else { return }
        print("TCPing 结果: 端口=\(result.port), 平均延迟=\(result.avgTime)ms")
    }
)

// 方法2：指定端口、探测次数和超时时间
networkDiagnosis?.tcpPing(
    "cloud.tencent.com",
    port: 443,             // 指定端口
    task_timeout: 5000,    // 超时时间（毫秒）
    count: 5,              // 探测次数
    output: diagOutput,
    complete: { result in
        guard let result = result else { return }
        print("✅ TCPing 探测完成:")
        print("  目标: \(result.ip ?? "N/A"):\(result.port)")
        print("  总探测数: \(result.count)")
        print("  成功数: \(result.count - result.loss)")
        print("  失败数: \(result.loss)")
        print("  最小延迟: \(result.minTime)ms")
        print("  最大延迟: \(result.maxTime)ms")
        print("  平均延迟: \(result.avgTime)ms")
        print("  标准差: \(result.stddev)ms")
    }
)

// 方法3：带自定义字段
var customFields = NSMutableDictionary()
customFields["service_type"] = "api"

networkDiagnosis?.tcpPing(
    "api.example.com",
    output: diagOutput,
    complete: { result in
        // 处理结果
    },
    customFiled: customFields
)
```

##### 4. HTTPing 探测

```swift
// 方法1：基础HTTP探测
networkDiagnosis?.httping(
    "https://cloud.tencent.com",
    output: diagOutput,
    complate: { result in
        guard let result = result else { return }
        print("✅ HTTPing 探测完成:")
        print("  状态码: \(result.statusCode)")
        print("  DNS解析: \(result.dnsLookupTime)ms")
        print("  TCP连接: \(result.tcpConnectionTime)ms")
        print("  SSL握手: \(result.sslHandshakeTime)ms")
        print("  总耗时: \(result.totalTime)ms")
        print("  响应大小: \(result.responseSize) bytes")
    }
)

// 方法2：带自定义字段
var customFields = NSMutableDictionary()
customFields["api_name"] = "user_login"
customFields["request_id"] = UUID().uuidString

networkDiagnosis?.httping(
    "https://api.example.com/login",
    output: diagOutput,
    complate: { result in
        guard let result = result else { return }
        if result.statusCode == 200 {
            print("✅ API探测成功")
        } else {
            print("⚠️ API状态异常: \(result.statusCode)")
        }
    },
    customFiled: customFields
)
```

##### 5. TraceRoute 探测

```swift
// 方法1：基础路由追踪
networkDiagnosis?.traceRoute(
    "cloud.tencent.com",
    output: diagOutput,
    complete: { result in
        guard let result = result else { return }
        print("✅ TraceRoute 完成:")
        print("  目标: \(result.ip ?? "N/A")")
        print("  总跳数: \(result.hops?.count ?? 0)")
        
        if let hops = result.hops as? [CLSTracerRouteHop] {
            for (index, hop) in hops.enumerated() {
                let ip = hop.ip ?? "*"
                let time = hop.durations?.compactMap { ($0 as? NSNumber)?.doubleValue }.first ?? 0
                print("  \(index + 1). \(ip)  \(time)ms")
            }
        }
    }
)

// 方法2：指定最大跳数
networkDiagnosis?.traceRoute(
    "cloud.tencent.com",
    output: diagOutput,
    complete: { result in
        // 处理结果
    },
    maxTtl: 30  // 最大30跳
)

// 方法3：带自定义字段
var customFields = NSMutableDictionary()
customFields["trace_scene"] = "network_diagnosis"

networkDiagnosis?.traceRoute(
    "cloud.tencent.com",
    output: diagOutput,
    complete: { result in
        // 处理结果
    },
    customFiled: customFields
)
```

##### 完整示例

详细的 Swift 网络探测完整示例代码请参考项目中的 `XcodeSwift/TencentCloudLogSwiftDemo/NetworkDiagnosisViewController.swift` 文件，包含：

- 完整的 UI 界面实现
- 四种探测方法的实际调用
- 探测结果的格式化显示
- 错误处理和异常情况处理
- 自定义输出处理器实现

#### 探测结果字段说明

##### Ping 结果 (CLSPingResult)

| 字段 | 类型 | 说明 |
|------|------|------|
| ip | String | 目标IP地址 |
| domain | String | 目标域名 |
| count | Int | 探测总次数 |
| loss | Int | 丢包数量 |
| minTime | Double | 最小延迟（毫秒） |
| maxTime | Double | 最大延迟（毫秒） |
| avgTime | Double | 平均延迟（毫秒） |
| stddev | Double | 延迟标准差（毫秒） |
| totalTime | Double | 总耗时（毫秒） |

##### TCPing 结果 (CLSTcpPingResult)

| 字段 | 类型 | 说明 |
|------|------|------|
| ip | String | 目标IP地址 |
| domain | String | 目标域名 |
| port | Int | 目标端口 |
| count | Int | 探测总次数 |
| loss | Int | 失败次数 |
| minTime | Double | 最小延迟（毫秒） |
| maxTime | Double | 最大延迟（毫秒） |
| avgTime | Double | 平均延迟（毫秒） |
| stddev | Double | 延迟标准差（毫秒） |
| totalTime | Double | 总耗时（毫秒） |

##### HTTPing 结果 (CLSHttpPingResult)

| 字段 | 类型 | 说明 |
|------|------|------|
| url | String | 请求URL |
| statusCode | Int | HTTP状态码 |
| dnsLookupTime | Double | DNS解析耗时（毫秒） |
| tcpConnectionTime | Double | TCP连接耗时（毫秒） |
| sslHandshakeTime | Double | SSL握手耗时（毫秒） |
| requestSendTime | Double | 请求发送耗时（毫秒） |
| responseWaitTime | Double | 响应等待耗时（毫秒） |
| responseReceiveTime | Double | 响应接收耗时（毫秒） |
| totalTime | Double | 总耗时（毫秒） |
| responseSize | Int | 响应大小（字节） |
| error | String | 错误信息（如有） |

##### TraceRoute 结果 (CLSTraceRouteResult)

| 字段 | 类型 | 说明 |
|------|------|------|
| ip | String | 目标IP地址 |
| domain | String | 目标域名 |
| hops | Array | 路由跳点数组 |

每个跳点 (CLSTracerRouteHop) 包含：

| 字段 | 类型 | 说明 |
|------|------|------|
| ip | String | 跳点IP地址 |
| durations | Array | 延迟数组（毫秒） |

#### 注意事项

1. **权限配置**：网络探测功能需要网络访问权限，请在 Info.plist 中配置必要的权限
2. **线程安全**：回调可能在后台线程执行，更新UI时需要切换到主线程
3. **错误处理**：建议检查结果对象是否为 nil，并处理探测失败的情况
4. **超时设置**：合理设置 task_timeout 参数，避免探测时间过长影响用户体验
5. **探测频率**：避免频繁进行网络探测，建议根据业务场景合理控制探测频率




