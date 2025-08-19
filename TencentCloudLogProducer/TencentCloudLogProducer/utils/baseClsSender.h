//
//  baseClsSender.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>
#import "ClsConfig.h"
#import "TencentCloudLogProducer/ClsLog.h"
NS_ASSUME_NONNULL_BEGIN

@interface baseClsSender : NSObject
- (void) initWithCLSConfig: (ClsConfig *)config;
- (BOOL) clsReport: (NSString *) data method: (NSString *) method domain: (NSString *) domain customFiled: (NSMutableDictionary*) customFiled;
@end

NS_ASSUME_NONNULL_END
