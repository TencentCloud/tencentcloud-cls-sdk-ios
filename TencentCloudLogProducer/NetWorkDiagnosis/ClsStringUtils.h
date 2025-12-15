//
//  CLSStringUtils.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface CLSStringUtils : NSObject

+ (NSString *) getSdkVersion;

+ (NSString *)sanitizeString:(id)value;
+ (NSNumber *)sanitizeNumber:(id)value;
+ (NSDictionary *)sanitizeHeaders:(NSDictionary *)headers;
+ (NSDictionary *)sanitizeDesc:(NSDictionary *)desc;
+ (NSDictionary *)sanitizeDictionary:(NSDictionary *)dict;
+ (id)sanitizeValue:(id)value;
+ (NSString *)convertToJSONString:(NSDictionary *)dictionary;
+ (NSString *)formatDateToMillisecondString:(NSDate *)date;
@end

NS_ASSUME_NONNULL_END
