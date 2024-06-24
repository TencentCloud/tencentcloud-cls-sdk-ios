//
//  baseSender.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>
#import "CLSConfig.h"
#import "Log.h"
NS_ASSUME_NONNULL_BEGIN

@interface baseSender : NSObject
- (void) initWithCLSConfig: (CLSConfig *)config;
- (BOOL) report: (NSString *) data method: (NSString *) method domain: (NSString *) domain customFiled: (NSMutableDictionary*) customFiled;
@end

NS_ASSUME_NONNULL_END
