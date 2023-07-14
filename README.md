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
#import <TencentCloudLogProducer.h>
```

### Podfile

```objective-c
pod 'TencentCloudLogProducer/Core'
```

### 配置

| 参数                         | 说明                                                         |                             取值                             |
| ---------------------------- | ------------------------------------------------------------ | :----------------------------------------------------------: |
| topic                        | 日志主题 ID ，通过接口SetTopic设置                           | 可在控制台获取https://console.cloud.tencent.com/cls/logset/desc |
| accessKeyId                  | 通过接口setAccessKeyId设置                                   | 参考官网文档：https://cloud.tencent.com/document/product/614/12445 |
| accessKey                    | 通过接口setAccessKeySecret设置                               | 参考官网文档：https://cloud.tencent.com/document/product/614/12445 |
| endpoint                     | 地域信息。通过接口setEndpoint设置，                          | 参考官方文档：https://cloud.tencent.com/document/product/614/18940 |
| logBytesPerPackage           | 缓存的日志包的大小上限，取值为1~5242880，单位为字节。默认为1024 * 1024。通过SetPackageLogBytes接口设置 |                        整数，单位字节                        |
| logCountPerPackage           | 缓存的日志包中包含日志数量的最大值，取值为1~10000，默认为1024条。通过SetPackageLogCount接口设置 |                             整数                             |
| packageTimeoutInMS           | 日志的发送逗留时间，如果缓存超时，则会被立即发送，单位为毫秒，默认为3000。通过SetPackageTimeout接口设置 |                        整数，单位毫秒                        |
| maxBufferBytes               | 单个Producer Client实例可以使用的内存的上限，超出缓存时add_log接口会立即返回失败。通过接口SetMaxBufferLimit设置 |                        整数，单位字节                        |
| sendThreadCount              | 发送线程数，默认为1。通过接口SetSendThreadCount设置          |                             整数                             |
| connectTimeoutSec            | 网络连接超时时间，默认为10s。通过接口SetConnectTimeoutSec设置 |                         整数，单位秒                         |
| sendTimeoutSec               | 读写超时，默认为15s。通过接口SetSendTimeoutSec设置           |                         整数，单位秒                         |
| destroyFlusherWaitTimeoutSec | flusher线程销毁最大等待时间，默认为1s。通过接口SetDestroyFlusherWaitSec设置 |                         整数，单位秒                         |
| destroySenderWaitTimeoutSec  | sender线程池销毁最大等待时间，默认为1s。通过接口SetDestroySenderWaitSec设置 |                         整数，单位秒                         |
| compressType                 | 数据上传时的压缩类型，默认为LZ4压缩，默认为1s。通过接口SetCompressType设置 |                0 不压缩，1 LZ4压缩， 默认为1                 |

### 使用demo


```objective-c
NSString* endpoint = @"project's_endpoint";
NSString* accesskeyid = @"your_accesskey_id";
NSString* accesskeysecret = @"your_accesskey_secret";
NSString* topic_id = @"your_topic";

    LogProducerConfig *config = [[LogProducerConfig alloc] initWithCoreInfo:[endpoint] accessKeyID:[accesskeyid] accessKeySecret:[accesskeysecret];
    [config SetTopic:topic_id];
    [config SetPackageLogBytes:1024*1024];
    [config SetPackageLogCount:1024];
    [config SetPackageTimeout:3000];
    [config SetMaxBufferLimit:64*1024*1024];
    [config SetSendThreadCount:1];
    [config SetConnectTimeoutSec:10];
    [config SetSendTimeoutSec:10];
    [config SetDestroyFlusherWaitSec:1];
    [config SetDestroySenderWaitSec:1];
    [config SetCompressType:1];
		
		//callback若传入空则不会回调
    LogProducerClient *client; = [[LogProducerClient alloc] initWithClsLogProducer:config callback:nil];
		Log* log = [[Log alloc] init];
    [log PutContent:@"cls_key_1" value:@"cls_value_1"];
    [log PutContent:@"cls_key_1" value:@"cls_value_2"];
    LogProducerResult result = [client PostLog:log];
```

## swift配置说明

### import

```swift
import TencentCloudLogProducer
```

### Podfile

```swift
pod 'TencentCloudLogProducer/Core'
```

### 配置

| 参数                         | 说明                                                         |                             取值                             |
| ---------------------------- | ------------------------------------------------------------ | :----------------------------------------------------------: |
| topic                        | 日志主题 ID ，通过接口SetTopic设置                           | 可在控制台获取https://console.cloud.tencent.com/cls/logset/desc |
| accessKeyId                  | 通过接口setAccessKeyId设置                                   | 参考官网文档：https://cloud.tencent.com/document/product/614/12445 |
| accessKey                    | 通过接口setAccessKeySecret设置                               | 参考官网文档：https://cloud.tencent.com/document/product/614/12445 |
| endpoint                     | 地域信息。通过接口setEndpoint设置                            | 参考官方文档：https://cloud.tencent.com/document/product/614/18940 |
| logBytesPerPackage           | 缓存的日志包的大小上限，取值为1~5242880，单位为字节。默认为1024 * 1024。通过SetPackageLogBytes接口设置 |                        整数，单位字节                        |
| logCountPerPackage           | 缓存的日志包中包含日志数量的最大值，取值为1~10000，默认为1024条。通过SetPackageLogCount接口设置 |                             整数                             |
| packageTimeoutInMS           | 日志的发送逗留时间，如果缓存超时，则会被立即发送，单位为毫秒，默认为3000。通过SetPackageTimeout接口设置 |                        整数，单位毫秒                        |
| maxBufferBytes               | 单个Producer Client实例可以使用的内存的上限，超出缓存时add_log接口会立即返回失败。通过接口SetMaxBufferLimit设置 |                        整数，单位字节                        |
| sendThreadCount              | 发送线程数，默认为1。通过接口SetSendThreadCount设置          |                             整数                             |
| connectTimeoutSec            | 网络连接超时时间，默认为10s。通过接口SetConnectTimeoutSec设置 |                         整数，单位秒                         |
| sendTimeoutSec               | 读写超时，默认为15s。通过接口SetSendTimeoutSec设置           |                         整数，单位秒                         |
| destroyFlusherWaitTimeoutSec | flusher线程销毁最大等待时间，默认为1s。通过接口SetDestroyFlusherWaitSec设置 |                         整数，单位秒                         |
| destroySenderWaitTimeoutSec  | sender线程池销毁最大等待时间，默认为1s。通过接口SetDestroySenderWaitSec设置 |                         整数，单位秒                         |
| compressType                 | 数据上传时的压缩类型，默认为LZ4压缩，默认为1s。通过接口SetCompressType设置 |                0 不压缩，1 LZ4压缩， 默认为1                 |

### 使用demo

```
//创建配置信息
let config = LogProducerConfig(coreInfo:"your endpoint", accessKeyID:"your accessKeyID", accessKeySecret:"your accessKeySecret")!
config.setTopic(utils.topic)
config.setPackageLogBytes(1024*1024)
config.setPackageLogCount(1024)
config.setPackageTimeout(3000)
config.setMaxBufferLimit(64*1024*1024)
config.setSendThreadCount(1)
config.setConnectTimeoutSec(10)
config.setSendTimeoutSec(10)
config.setDestroyFlusherWaitSec(1)
config.setDestroySenderWaitSec(1)
config.setCompressType(1)
let tv = self.resText;

//构建client
client = LogProducerClient(clsLogProducer:config, callback:callbackFunc)
```

## 网络探测

### import

```objective-c
#import "CLSNetworkDiagnosis.h"
#import "CLSAdapter.h"
#import "CLSNetDiag.h"
```

- CLSNetworkDiagnosis.h 网络探测核心功能入口文件
- CLSAdapter.h 插件管理器
- CLSNetDiag.h 网络探测output输出文件，用户可自定义实现write方法

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
| accessKeyId     | 密钥id。参考官网文档：https://cloud.tencent.com/document/product/614/12445 |
| accessKeySecret | 密钥。参考官网文档：https://cloud.tencent.com/document/product/614/12445 |
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
CLSConfig *config = [[CLSConfig alloc] init];
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
    
CLSAdapter *clsAdapter = [CLSAdapter sharedInstance];
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

- 方法二

```objective-c
/**
* @param host   目标 host，如 cloud.tencent.com
* @param size   数据包大小
* @param output   输出 callback
* @param callback 回调 callback
* @param count 探测次数
*/
- (void)ping:(NSString*)host size:(NSUInteger)size output:(id<CLSOutputDelegate>)output complete:(CLSPingCompleteHandler)complete count:(NSInteger)count;
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
* @param count.   探测次数
* @param output   输出 callback                
* @param callback 回调 callback
*/
- (void)tcpPing:(NSString*)host port:(NSUInteger)port count:(NSInteger)count output:(id<CLSOutputDelegate>)output complete:(CLSTcpPingCompleteHandler)complete;
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
*
* @param host 目标 host，如：cloud.tencent.com
* @param maxTtl 最大存活跳数
* @param countPerRoute
* @param output   输出 callback
* @param callback 回调 callback
*/
- (void)traceRoute:(NSString*)host output:(id<CLSOutputDelegate>)output complete:(CLSTraceRouteCompleteHandler)complete maxTtl:(NSInteger)maxTtl;
```

#### httping方法

```objective-c
/**
*
* @param url 如：https://ap-guangzhou.cls.tencentcs.com/ping
* @param output   输出 callback
* @param callback 回调 callback
*/
- (void) httping:(NSString*)url output:(id<CLSOutputDelegate>)output complate:(CLSHttpCompleteHandler)complate;
```



## 日志检索

- ##### 接口api文档参考官网：https://cloud.tencent.com/document/product/614/16875

- ##### 接口描述

  - 请求入参描述

  | 字段名       | 类型   | 位置  | 必须 | 含义                                                         |
  | :----------- | :----- | :---- | :--- | :----------------------------------------------------------- |
  | logset_id    | string | query | 是   | 要查询的 logset ID                                           |
  | topic_ids    | string | query | 是   | 要查询的 topic ID                                            |
  | start_time   | string | query | 是   | 要查询的日志的起始时间，格式 YYYY-mm-dd HH:MM:SS             |
  | end_time     | string | query | 是   | 要查询的日志的结束时间，格式 YYYY-mm-dd HH:MM:SS             |
  | query_string | string | query | 是   | 查询语句，详情参考 [检索语法与规则](https://cloud.tencent.com/document/product/614/47044) |
  | limit        | int    | query | 是   | 单次要返回的日志条数，单次返回的最大条数为100                |
  | context      | string | query | 否   | 加载更多使用，透传上次返回的 context 值，获取后续的日志内容，通过游标最多可获取10000条，请尽可能缩小时间范围 |
  | sort         | string | query | 否   | 按时间排序 asc（升序）或者 desc（降序），默认为 desc         |

  - 响应描述

  | 字段名   | 类型                   | 必有 | 含义                     |
  | :------- | :--------------------- | :--- | :----------------------- |
  | context  | string                 | 是   | 获取更多检索结果的游标   |
  | listover | bool                   | 是   | 搜索结果是否已经全部返回 |
  | results  | JsonArray（LogObject） | 是   | 日志内容信息             |

  - LogObject 格式如下

  | 字段名     | 类型   | 必有 | 含义                |
  | :--------- | :----- | :--- | :------------------ |
  | topic_id   | string | 是   | 日志属于的 topic ID |
  | topic_name | string | 是   | 日志主题的名字      |
  | timestamp  | string | 是   | 日志时间            |
  | content    | string | 是   | 日志内容            |
  | filename   | string | 是   | 采集路径            |
  | source     | string | 是   | 日志来源设备        |

- ##### 接口描述

```objective-c
/*
@region 地域信息
@secretid 密钥id
@secretkey 密钥
@logsetid 日志集id
@topicids topic列表
@starttime 要查询的日志的起始时间，格式 YYYY-mm-dd HH:MM:SS
@endtime 要查询的日志的结束时间，格式 YYYY-mm-dd HH:MM:SS
@query 查询语句
@limit 单次要返回的日志条数，单次返回的最大条数为100
@context 加载更多使用，透传上次返回的 context 值，获取后续的日志内容，通过游标最多可获取10000条，请尽可能缩小时间范围
@sort 按时间排序 asc（升序）或者 desc（降序），默认为 desc
*/
-(SearchReult) SearchLog:(NSString*)region secretid:(NSString*) secretid
             secretkey:(NSString*) secretkey
              logsetid:(NSString*) logsetid
              topicids:(NSArray*) topicids
             starttime:(NSString*) starttime
               endtime:(NSString*) endtime
                 query:(NSString*) query
                 limit:(NSInteger)limit
               context:(NSString*)context
                  sort:(NSString*)sort
                    
struct SearchReult
{
    NSInteger statusCode; //返回码
    NSString* message; //响应消息回包 json格式
    NSString* requestID; //本次请求序列号
};
```

- ##### 使用demo

```objective-c
//初始化LogSearchClient对象 
LogSearchClient *sclient = [[LogSearchClient alloc] init];
//topicid以数组的形式传递
NSArray *topics = [NSArray arrayWithObjects:@"your topicid",nil];
    SearchReult r = [sclient SearchLog:@"ap-guangzhou.cls.tencentcs.com" secretid:@"" secretkey:@"" logsetid:@"" topicids:topics starttime:@"" endtime:@"" query:@"" limit:10 context:nil sort:nil];
    NSLog(@"%@",r.message);

//释放资源
[sclient DestroyLogSearch];
```
