# NetWorkDiagnosis 测试用例运行指南

## 📁 测试文件
- **测试类**: `TencentCloudLogDemoTests.m`
- **测试框架**: XCTest
- **测试类型**: 单元测试 + 集成测试

---

## 🚀 快速开始

### 1. 配置测试环境

打开 `TencentCloudLogDemoTests.m`，在 `setUp` 方法中配置你的 CLS 凭证：

```objectivec
- (void)setUp {
    [super setUp];
    
    self.testConfig = [[ClsLogSenderConfig alloc] init];
    self.testConfig.endpoint = @"ap-guangzhou.cls.tencentcs.com";
    self.testConfig.accessKeyId = @"YOUR_ACCESS_KEY_ID";  // 替换为真实的 AccessKey
    self.testConfig.accessKey = @"YOUR_ACCESS_KEY";        // 替换为真实的 AccessKey
    
    [[ClsNetworkDiagnosis sharedInstance] setupLogSenderWithConfig:self.testConfig];
}
```

### 2. 运行测试

#### 方法 1: 运行所有测试
1. 在 Xcode 中打开项目
2. 选择 scheme: `TencentCloudLogDemo`
3. 按 `Cmd + U` 或点击 `Product > Test`

#### 方法 2: 运行单个测试用例
1. 打开 `TencentCloudLogDemoTests.m`
2. 点击测试方法左侧的 ◇ 图标
3. 或右键点击测试方法 > `Run "testMethodName"`

#### 方法 3: 使用测试导航器
1. 按 `Cmd + 6` 打开测试导航器
2. 展开 `TencentCloudLogDemoTests`
3. 点击任意测试用例运行

#### 方法 4: 命令行运行
```bash
cd /Users/haolv/WorkSpace/cls_team/sdk/tencentcloud-cls-sdk-ios/Xcode/TencentCloudLogDemo
xcodebuild test -scheme TencentCloudLogDemo -destination 'platform=iOS Simulator,name=iPhone 14'
```

---

## 📊 测试用例列表

### HTTP Ping 测试 (8 个)
| 测试方法 | 测试内容 | 优先级 |
|---------|---------|--------|
| `testBasicHttpsRequest` | 基本 HTTPS 请求探测 | P0 |
| `testBasicHttpRequest` | HTTP 请求探测（非加密） | P0 |
| `testHttpingOnWiFi` | WiFi 网卡探测 | P0 |
| `testMultipleInterfacesHttping` | 多网卡同时探测 | P0 |
| `testCustomUserExtension` | 自定义用户扩展字段 | P1 |
| `testInvalidDomain` | 无效域名处理 | P0 |

### TCP Ping 测试 (3 个)
| 测试方法 | 测试内容 | 优先级 |
|---------|---------|--------|
| `testBasicTcpPing` | 基本 TCP 端口连通性测试 | P0 |
| `testTcpPingHttpsPort` | HTTPS 端口测试 (443) | P0 |
| `testMultipleTcpPingStatistics` | 多次 Ping 统计 | P0 |

### ICMP Ping 测试 (2 个)
| 测试方法 | 测试内容 | 优先级 |
|---------|---------|--------|
| `testBasicIcmpPing` | 基本 ICMP Ping | P0 |
| `testCustomPacketSize` | 自定义包大小 | P1 |

### DNS 解析测试 (2 个)
| 测试方法 | 测试内容 | 优先级 |
|---------|---------|--------|
| `testBasicDnsResolution` | 基本 DNS 解析 | P0 |
| `testCustomDnsServer` | 自定义 DNS 服务器 | P1 |

### MTR 测试 (1 个)
| 测试方法 | 测试内容 | 优先级 |
|---------|---------|--------|
| `testBasicMtr` | 基本 MTR 路由跟踪 | P0 |

### 性能测试 (1 个)
| 测试方法 | 测试内容 | 优先级 |
|---------|---------|--------|
| `testPerformanceConcurrentHttping` | 并发 HTTP Ping 性能测试 | P2 |

**总计**: 17 个测试用例

---

## 🔧 测试环境要求

### 必需条件
- ✅ Xcode 12.0+
- ✅ iOS 10.0+ 模拟器或真机
- ✅ 有效的网络连接
- ✅ 有效的 CLS AccessKey 配置

### 推荐条件
- ✅ 使用真机测试（某些网络功能模拟器可能受限）
- ✅ 连接到 WiFi 网络（测试多网卡功能）
- ✅ iOS 13.0+ 设备（完整功能支持）

---

## 📝 测试结果查看

### Xcode 测试报告
1. 运行测试后，在 `Report Navigator (Cmd + 9)` 中查看
2. 点击最新的测试报告
3. 展开查看每个测试用例的详细结果

### 控制台日志
测试运行时，控制台会输出详细日志：
```
[HTTP] 网卡: 192.168.1.100, 类型: WiFi, 状态: 200, 耗时: 123ms
[TCP] 网卡: 192.168.1.100, 平均延迟: 45ms, 成功/失败: 5/0
[PING] 网卡: 192.168.1.100, 目标: 14.215.177.38, 平均延迟: 23ms, 丢包率: 0%
[DNS] 查询主机: www.baidu.com, DNS 服务器: 8.8.8.8, 查询时间: 67ms
[MTR] 跳 1: 192.168.1.1 (延迟: 2ms)
```

### 测试覆盖率
1. 在 Xcode 中 `Product > Scheme > Edit Scheme`
2. 选择 `Test` 标签
3. 勾选 `Code Coverage` > 选择 `TencentCloudLogProducer`
4. 运行测试后查看覆盖率报告

---

## ⚠️ 注意事项

### 1. 网络依赖
- 某些测试需要真实的网络连接
- 建议在稳定的网络环境下运行测试
- WiFi 网卡测试需要设备连接到 WiFi

### 2. 超时设置
- 网络测试默认超时时间为 30-120 秒
- 如果网络较慢，可能需要调整超时时间
- 可在 `waitForExpectationsWithTimeout:` 中修改

### 3. 权限要求
- ICMP Ping 可能需要特殊权限
- 某些网络诊断功能在模拟器上可能受限
- 建议在真机上运行完整测试

### 4. 测试数据
- 测试使用公共域名（baidu.com, google.com 等）
- 如果某些域名不可访问，测试可能失败
- 可根据实际情况修改测试域名

---

## 🐛 故障排查

### 问题 1: 测试失败 - "响应为空"
**原因**: 网络不可用或配置错误  
**解决**: 
- 检查网络连接
- 检查 AccessKey 配置是否正确
- 检查目标域名是否可访问

### 问题 2: WiFi 测试被跳过
**原因**: 设备未连接到 WiFi  
**解决**: 
- 连接到 WiFi 网络
- 或修改测试用例跳过条件

### 问题 3: 超时错误
**原因**: 网络延迟较大或目标不可达  
**解决**: 
- 增加超时时间
- 更换测试目标域名
- 检查防火墙设置

### 问题 4: 编译错误 - 找不到头文件
**原因**: 依赖未正确安装  
**解决**: 
```bash
cd Xcode/TencentCloudLogDemo
pod install
```

---

## 📚 参考资源

- [完整测试用例文档](../../../NETWORK_DIAGNOSIS_TEST_CASES.md)
- [项目上下文文档](../../../PROJECT_CONTEXT.md)
- [代码审查报告](../../../CLSHttpingV2_CODE_REVIEW.md)
- [官方文档](https://cloud.tencent.com/document/product/614)

---

## 🔄 持续集成

### GitHub Actions 示例配置

```yaml
name: iOS Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Install CocoaPods
      run: |
        cd Xcode/TencentCloudLogDemo
        pod install
    
    - name: Run Tests
      run: |
        cd Xcode/TencentCloudLogDemo
        xcodebuild test \
          -workspace TencentCloudLogDemo.xcworkspace \
          -scheme TencentCloudLogDemo \
          -destination 'platform=iOS Simulator,name=iPhone 14' \
          CODE_SIGN_IDENTITY="" \
          CODE_SIGNING_REQUIRED=NO
```

---

**最后更新**: 2025-12-04  
**维护者**: CLS iOS SDK Team
