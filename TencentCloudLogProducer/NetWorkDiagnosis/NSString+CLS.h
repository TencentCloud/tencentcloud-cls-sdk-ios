//
//  NSString+CLS.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSString (CLS)

/**
 * Encode string with base64.
 */
- (NSString *) base64Encode;

/**
 * Decode string with base64.
 */
- (NSString *) base64Decode;

/**
 * String to dictionary.
 */
- (NSDictionary *) toDictionary;

/**
 * String with dictionary.
 */
+ (NSString *) stringWithDictionary: (NSDictionary *) dictionary;

@end

NS_ASSUME_NONNULL_END
