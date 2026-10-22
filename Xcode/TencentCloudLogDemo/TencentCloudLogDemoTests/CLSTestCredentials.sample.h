//
//  CLSTestCredentials.sample.h
//  TencentCloudLogDemoTests
//
//  敏感信息外置文件：真实值放在 CLSTestCredentials.h（gitignore）。
//  本文件（.sample）提交到仓库作为占位模板。
//
//  使用方法：
//   1. 拷贝为 CLSTestCredentials.h：
//        cp CLSTestCredentials.sample.h CLSTestCredentials.h
//   2. 在 CLSTestCredentials.h 中填入自己的腾讯云 CLS 测试凭据
//   3. .gitignore 已排除 CLSTestCredentials.h，不会误提交
//
//  若未配置 CLSTestCredentials.h，所有引用这些常量的测试仍能编译，
//  只是对真实服务端的请求必定失败——不影响本地逻辑/存储/诊断类测试通过。
//

#ifndef CLSTestCredentials_h
#define CLSTestCredentials_h

/// Base64 编码的 netToken：生成规则见 CLS 控制台 SDK 接入文档
///   payload = { n_a_id, uin, key, region, topic_id }
///   替换为自己的测试租户 netToken
static NSString *const kCLSTestNetToken = @"REPLACE_WITH_YOUR_NET_TOKEN_BASE64";

/// CLS 日志服务 endpoint，形如 "ap-guangzhou.cls.tencentcs.com"
static NSString *const kCLSTestEndpoint = @"REPLACE_WITH_YOUR_CLS_ENDPOINT";

/// 腾讯云 API 的 SecretId / SecretKey（请使用子账号或临时凭据，勿用主账号）
static NSString *const kCLSTestSecretId  = @"REPLACE_WITH_YOUR_SECRET_ID";
static NSString *const kCLSTestSecretKey = @"REPLACE_WITH_YOUR_SECRET_KEY";

/// 测试用 TopicID（UUID 字符串）
static NSString *const kCLSTestTopicId = @"REPLACE_WITH_YOUR_TOPIC_ID";

#endif /* CLSTestCredentials_h */
