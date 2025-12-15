//
//  CLSResponse.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/13.
//

#import <Foundation/Foundation.h>
#import "CLSResponse.h"

@implementation CLSResponse

#pragma mark - 初始化方法

- (instancetype)initWithContent:(NSString *)content{
    self = [super init];
    if (self) {
        _content = [content copy];
    }
    return self;
}

#pragma mark - 便捷构造方法

+ (CLSResponse *)complateResultWithContent:(NSDictionary *)reportData {
    // 将字典转换为JSON字符串
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:reportData
                                                      options:NSJSONWritingPrettyPrinted
                                                        error:nil];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    
    return [[CLSResponse alloc] initWithContent:jsonString];
                                    
}

- (NSString *)description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: %p>\n", [self class], self];
    
    if (self.content) {
        [description appendFormat:@"Content: %@\n", self.content];
    }
    return description;
}

@end
