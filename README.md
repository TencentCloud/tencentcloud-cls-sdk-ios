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

```
pod 'TencentCloudLogProducer'
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



## 使用demo


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
