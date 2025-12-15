//
//  CLSUserInfo.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CLSUserInfo : NSObject
@property(nonatomic, copy) NSString *uid;
@property(nonatomic, copy) NSString *channel;
@property(nonatomic, readonly) NSMutableDictionary<NSString *, NSString *> *ext;

+ (instancetype) userInfo;
- (void) addExt: (NSString *) value key: (NSString *) key;

@end

NS_ASSUME_NONNULL_END
