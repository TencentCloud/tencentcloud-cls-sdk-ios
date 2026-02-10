//
//  CLSDnsping.h
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/20.
//

#import <Foundation/Foundation.h>
#import "ClsProtocols.h"

NS_ASSUME_NONNULL_BEGIN
#pragma mark - 多接口DNS测试类

@interface CLSMultiInterfaceDns : CLSBaseFields

@property (nonatomic, strong, readonly) CLSDnsRequest *request;
- (instancetype)initWithRequest:(CLSDnsRequest *)request;
- (void)start:(CompleteCallback)complate;
@end

NS_ASSUME_NONNULL_END
