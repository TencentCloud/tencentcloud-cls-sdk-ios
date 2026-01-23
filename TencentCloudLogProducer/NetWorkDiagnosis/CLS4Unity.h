//
//  CLS4Unity.h
//  TencentCloudLogProducer
//
//  Created by hanclli on 2025/10/23.
//  Updated for network detection API v2
//
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// 初始化接口
void cls_init(const char *endpoint, const char *accessKey, const char *accessSecret, const char *topicId);
void cls_init_with_net_token(const char *endpoint, const char *accessKey, const char *accessSecret, const char *netToken);
void set_userex(NSDictionary* userEx);

// ICMP Ping 探测
void cls_ping(const char* host, unsigned int size, unsigned int maxTimes, unsigned int timeout, 
              int interval, int prefer, const char* appKey, const char* pageName,
              void(*callback)(const char*), NSDictionary* userEx, NSDictionary* detectEx, const char* traceId);

// TCP 连接探测
void cls_tcp_ping(const char* host, unsigned int port, unsigned int maxTimes, unsigned int timeout,
                  const char* appKey, const char* pageName,
                  void(*callback)(const char*), NSDictionary* userEx, NSDictionary* detectEx, const char* traceId);

// HTTP 探测
void cls_http_ping(const char* host, unsigned int maxTimes, unsigned int timeout, 
                   int enableSSLVerification, const char* appKey, const char* pageName,
                   void(*callback)(const char*), NSDictionary* userEx, NSDictionary* detectEx, const char* traceId);

// DNS 解析探测
void cls_dns_ping(const char* host, const char* nameServer, unsigned int timeout, 
                  int prefer, const char* appKey, const char* pageName,
                  void(*callback)(const char*), NSDictionary* userEx, NSDictionary* detectEx, const char* traceId);

// MTR 路径探测
void cls_mtr_ping(const char* host, unsigned int maxTTL, unsigned int maxTimes, unsigned int timeout,
                  const char* protocol, int prefer, const char* appKey, const char* pageName,
                  void(*callback)(const char*), NSDictionary* userEx, NSDictionary* detectEx, const char* traceId);

#ifdef __cplusplus
}
#endif


