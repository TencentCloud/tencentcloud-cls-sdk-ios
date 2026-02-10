# 网络诊断测试用例文档

## 📋 概述

本测试套件基于**网络探测字段规范文档** (`field-specification.md`) 生成，全面验证 iOS SDK 网络诊断功能的字段完整性和数据正确性。

---

## 🎯 测试覆盖范围

### 1️⃣ **ICMP Ping 测试** (`testPingFieldsCompleteness`)
- ✅ 公共字段验证（纳秒时间戳）
- ✅ Resource 字段验证（32个字段）
- ✅ Ping 探测信息验证（15+字段，毫秒时间）
- ✅ netInfo GEO 信息验证（9个字段）
- ✅ 扩展字段验证（detectEx、userEx）

**关键验证点**:
- `method` = `"ping"`
- `src` = `"app"`
- 时间单位：`total`, `latency_*` 均为毫秒
- 统计字段：`count`, `loss`, `responseNum`, `exceptionNum`, `bindFailed`

---

### 2️⃣ **HTTP/HTTPS 测试** (`testHttpFieldsCompleteness`)
- ✅ HTTP 基础信息验证（18+字段）
- ✅ headers 响应头验证
- ✅ **desc 生命周期打点验证（15个时间点）**
- ✅ 时间顺序验证（`callStart` → `callEnd`）

**关键验证点**:
- `method` = `"http"`
- HTTP 状态码、协议版本、带宽等
- **desc 时间点**: `callStart`, `dnsStart`, `dnsEnd`, `connectStart`, `secureConnectStart`, `secureConnectEnd`, `connectionAcquired`, `requestHeaderStart`, `requestHeaderEnd`, `responseHeadersStart`, `responseHeaderEnd`, `responseBodyStart`, `responseBodyEnd`, `connectionReleased`, `callEnd`
- headers 内容以服务端返回为准

---

### 3️⃣ **TCP Ping 测试** (`testTcpPingFieldsCompleteness`)
- ✅ TCP 连接探测验证
- ✅ 端口字段验证（`port`）
- ✅ 延迟统计验证（`latency_min`, `latency_max`, `latency`, `stddev`）

**关键验证点**:
- `method` = `"tcpping"`
- `port` 字段必填
- 时间单位为毫秒

---

### 4️⃣ **DNS 解析测试** (`testDnsFieldsCompleteness`)
- ✅ DNS 查询字段验证
- ✅ QUESTION-SECTION / ANSWER-SECTION JSON 格式验证
- ✅ DNS 统计字段验证（QUERY, ANSWER, AUTHORITY, ADDITIONAL）

**关键验证点**:
- `method` = `"dns"`
- `status` = `"NOERROR"` 或其他状态
- `QUESTION-SECTION` 和 `ANSWER-SECTION` 为 JSON 数组字符串
- DNS 服务器地址在 `host_ip` 字段

---

### 5️⃣ **MTR (TraceRoute) 测试** (`testMtrFieldsCompleteness`)
- ✅ 路径追踪基础信息验证
- ✅ paths 数组验证（动态字段）
- ✅ 每一跳详情验证（`hop`, `ip`, `latency_*`, `loss`, `responseNum`）

**关键验证点**:
- `method` = `"mtr"`
- `paths` 数组包含路径详情
- 每条路径的 `result` 数组包含每一跳的统计信息

---

## ⏰ 重要时间单位约定

### 🔴 **纳秒 (nanosecond)** - 公共字段
```objectivec
data[@"start"]     // 纳秒时间戳（值 > 1000000000000）
data[@"duration"]  // 纳秒耗时
data[@"end"]       // 纳秒时间戳
```

### 🟢 **毫秒 (millisecond)** - 探测字段
```objectivec
origin[@"total"]          // Ping 总耗时（毫秒）
origin[@"latency_min"]    // 最小延迟（毫秒）
origin[@"requestTime"]    // HTTP 请求时间（毫秒）
desc[@"callStart"]        // HTTP 生命周期时间点（毫秒）
```

**验证方法**:
```objectivec
// 公共字段：值应该很大（纳秒）
XCTAssertGreaterThan(start, 1000000000000LL, @"start 应为纳秒时间戳");

// 探测字段：值应该合理（毫秒，通常 < 10000）
XCTAssertLessThan(total, 10000.0, @"total 应为毫秒");
```

---

## 🧪 边界条件测试

### `testTimeUnitConsistency` - 时间单位一致性
验证公共字段（纳秒）与探测字段（毫秒）的时间一致性：
```objectivec
durationMs = duration / 1000000.0; // 纳秒转毫秒
XCTAssertLessThan(fabs(durationMs - total), 1000.0, @"时间应接近");
```

### `testEmptyExtensionFields` - 空扩展字段
验证未设置 `detectEx` 和 `userEx` 时，字段应为空对象 `{}`，而非 `nil`：
```objectivec
XCTAssertNotNil(detectEx, @"detectEx 应为 {}，而非 nil");
XCTAssertTrue([detectEx isKindOfClass:[NSDictionary class]]);
```

### `testHttpDescTimeSequence` - HTTP 生命周期时间顺序
验证 15 个时间点的顺序正确性：
```objectivec
callStart <= dnsStart <= dnsEnd <= connectStart <= ... <= callEnd
```

---

## 🌍 GEO 信息验证 (`validateNetInfo`)

所有探测方法的响应都应包含 `netInfo` 字段（GEO 信息）：

```objectivec
netInfo[@"dns"]          // 本地 DNS
netInfo[@"defaultNet"]   // 默认网络（WIFI/4G/5G）
netInfo[@"usedNet"]      // 实际使用网络
netInfo[@"client_ip"]    // 公网出口 IP

// GEO 信息（由客户端调用接口获取）
netInfo[@"country_id"]   // 国家 ID（如 CN）
netInfo[@"isp_en"]       // 运营商（如 China-Unicom）
netInfo[@"province_en"]  // 省份（如 Beijing）
netInfo[@"city_en"]      // 城市（如 Beijing）
netInfo[@"country_en"]   // 国家（如 China）
```

---

## 📦 扩展字段验证 (`validateExtensionFields`)

### detectEx（业务拓展字段）
- **设置时机**: 调用探测方法时传入
- **作用域**: 仅对当次探测生效
- **示例**:
```objectivec
request.detectEx = @{@"scene": @"startup"};
```

### userEx（用户自定义字段）
- **设置时机**: SDK 初始化时设置
- **作用域**: 全局生效
- **示例**:
```objectivec
request.userEx = @{@"user_id": @"12345"};
```

### 空字段处理
如果未设置，应返回空对象 `{}`，而非 `nil`：
```json
{
  "detectEx": {},
  "userEx": {}
}
```

---

## 🔧 公共字段验证 (`validateCommonFields`)

所有探测方法都会验证以下公共结构：

### 1. 公共字段（6个）
- `name`, `traceID`, `start`, `duration`, `end`, `service`

### 2. Resource 字段（26个）
#### 应用信息
- `resource.app.name`, `resource.app.version`, `resource.app.versionCode`

#### 设备信息
- `resource.device.brand`, `resource.device.id`, `resource.device.manufacturer`
- `resource.device.model.identifier`, `resource.device.model.name`, `resource.device.resolution`

#### 系统信息
- `resource.host.arch`, `resource.host.name`, `resource.host.type`
- `resource.os.name`, `resource.os.version`, `resource.os.type`
- `resource.os.root`, `resource.os.description`

#### 网络信息
- `resource.carrier`, `resource.net.access`, `resource.net.access_subtype`

#### SDK 信息
- `resource.sdk.language`, `resource.cls.sdk.version`

---

## 🚀 运行测试

### 方法 1: Xcode GUI
1. 打开 `TencentCloudLogDemo.xcodeproj`
2. 选择测试 Target: `TencentCloudLogDemoTests`
3. 选择测试类: `CLSNetworkDiagnosisTests`
4. 点击 ▶️ 运行测试

### 方法 2: 命令行
```bash
cd Xcode/TencentCloudLogDemo

# 运行所有网络诊断测试
xcodebuild test \
  -scheme TencentCloudLogDemo \
  -destination 'platform=iOS Simulator,name=iPhone 14' \
  -only-testing:TencentCloudLogDemoTests/CLSNetworkDiagnosisTests

# 运行单个测试
xcodebuild test \
  -scheme TencentCloudLogDemo \
  -destination 'platform=iOS Simulator,name=iPhone 14' \
  -only-testing:TencentCloudLogDemoTests/CLSNetworkDiagnosisTests/testPingFieldsCompleteness
```

---

## 📊 测试统计

### 基础功能测试

| 测试类型 | 测试方法 | 验证字段数 | 超时时间 |
|---------|---------|----------|---------|
| Ping | `testPingFieldsCompleteness` | 50+ | 20s |
| HTTP | `testHttpFieldsCompleteness` | 70+ | 20s |
| TCP Ping | `testTcpPingFieldsCompleteness` | 45+ | 20s |
| DNS | `testDnsFieldsCompleteness` | 35+ | 20s |
| MTR | `testMtrFieldsCompleteness` | 40+ (动态) | 35s |
| 边界测试 | `testTimeUnitConsistency` | - | 15s |
| 边界测试 | `testEmptyExtensionFields` | - | 15s |
| 边界测试 | `testHttpDescTimeSequence` | - | 20s |

### 多网卡探测测试（新增 🆕）

| 测试类型 | 测试方法 | 验证重点 | 超时时间 |
|---------|---------|---------|---------|
| 多网卡 ICMP Ping | `testMultiInterfaceICMPPing` | 多网卡并发探测 | 20s |
| 多网卡 TCP Ping | `testMultiInterfaceTCPPing` | 网卡绑定、连接统计 | 25s |
| 多网卡 DNS | `testMultiInterfaceDNS` | DNS 解析正确性 | 20s |
| 多网卡 HTTP | `testMultiInterfaceHTTP` | HTTP 请求完整性 | 30s |
| 多网卡 MTR | `testMultiInterfaceMTR` | 路由追踪准确性 | 40s |
| 单网卡降级 | `testMultiInterfaceFallbackToSingleInterface` | 降级逻辑正确性 | 15s |
| 网卡绑定失败 | `testMultiInterfaceBindFailure` | 错误统计准确性 | 15s |

**总计**: 15 个测试方法，覆盖 280+ 字段验证 + 多网卡场景全覆盖

📄 **详细文档**: [多网卡测试报告](../../../reports/multi_interface_test_report.md)

---

## ⚠️ 注意事项

### 1. 网络依赖
测试需要访问真实网络（`www.tencentcloud.com`），确保：
- ✅ 测试设备/模拟器有网络连接
- ✅ 目标域名可访问
- ✅ 防火墙/代理配置正确

### 2. 超时设置
- 普通探测：15-20秒
- MTR 测试：35秒（路径追踪耗时较长）

### 3. GEO 信息依赖
测试假设 SDK 已正确实现 GEO 信息获取接口调用。如果接口未实现，`netInfo` GEO 字段验证会失败。

### 4. 动态字段
以下字段为动态内容，测试仅验证存在性，不验证具体值：
- `headers`（HTTP 响应头，依赖服务端返回）
- `ANSWER-SECTION`（DNS 解析结果）
- `paths[].result`（MTR 路径跳数，依赖网络拓扑）

---

## 🐛 常见问题排查

### 问题 1: 测试超时
**原因**: 网络连接慢或目标主机不可达  
**解决**: 增加超时时间或更换测试域名

### 问题 2: JSON 解析失败
**原因**: 响应 `content` 不是有效 JSON  
**解决**: 检查 `CLSResponse` 的 `complateResultWithContent` 实现

### 问题 3: 时间单位错误
**原因**: 公共字段使用毫秒而非纳秒  
**解决**: 检查时间戳生成代码，确保使用 `mach_absolute_time()` 或 `CFAbsoluteTimeGetCurrent() * 1e9`

### 问题 4: GEO 字段缺失
**原因**: 未实现 GEO 信息获取接口  
**解决**: 实现探测完成后调用 `DescribeGeoInfo` 接口

### 问题 5: HTTP desc 时间顺序错误
**原因**: 生命周期打点顺序错误或未打点  
**解决**: 检查 `CLSHttpingV2.m` 中的打点代码，确保 15 个时间点按顺序记录

---

## 📚 参考文档

- **字段规范文档**: `.codebuddy/skills/cls-ios-sdk/references/field-specification.md`
- **产品需求文档**: https://doc.weixin.qq.com/doc/w3_AWUAJgaUAFcCNM2vm7VdcQTCU5Xvx
- **API 参考**: `.codebuddy/skills/cls-ios-sdk/references/api-reference.md`
- **测试指南**: `.codebuddy/skills/cls-ios-sdk/references/testing-guide.md`

---

## 🎯 下一步

### 待补充测试
1. **错误场景测试**
   - 网络不可达
   - 超时处理
   - 无效参数

2. **性能测试**
   - 并发探测
   - 内存使用
   - 探测频率限制

3. **线程安全测试**
   - 多线程调用
   - 回调线程验证

### 持续改进
- 添加测试覆盖率报告
- 集成 CI/CD 自动化测试
- 添加性能基准测试

### ✅ 已完成
- ✅ 多网卡探测全覆盖测试（2025-12-19）
  - ICMP Ping、TCP Ping、DNS、HTTP、MTR 多网卡场景
  - 单网卡降级测试
  - 网卡绑定失败测试
  - 详见 [多网卡测试报告](../../../reports/multi_interface_test_report.md)

---

**生成日期**: 2025-12-18  
**基于规范**: CLS 网络探测字段规范 v1.0  
**测试框架**: XCTest  
