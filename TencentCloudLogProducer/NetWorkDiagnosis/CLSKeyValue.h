//
//  CLSKeyValue.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CLSKeyValue : NSObject

@property(nonatomic, strong) NSString* key;
@property(nonatomic, strong) NSString* value;

+ (CLSKeyValue *) create: (NSString*) key value: (NSString*) value;

+ (CLSKeyValue *) key: (NSString *) key value: (NSString *) value;

@end

NS_ASSUME_NONNULL_END
