//
//  CLSPrivocyUtils.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CLSPrivocyUtils : NSObject
- (void) internal_setEnablePrivocy: (BOOL) enablePrivocy;
- (BOOL) internal_isEnablePrivocy;
+ (void) setEnablePrivocy: (BOOL) enablePrivocy;
+ (BOOL) isEnablePrivocy;
@end

NS_ASSUME_NONNULL_END
