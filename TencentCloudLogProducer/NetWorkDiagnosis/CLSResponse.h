//
//  CLSResponse.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/13.
//

#import <Foundation/Foundation.h>

@interface CLSResponse : NSObject
@property(nonatomic, readonly, copy) NSString *content;

- (instancetype)initWithContent:(NSString *)content;
                     

// 可以添加成功/失败的便捷构造方法
+ (CLSResponse *)complateResultWithContent:(NSDictionary *)reportData;
- (NSString *)description;
@end
