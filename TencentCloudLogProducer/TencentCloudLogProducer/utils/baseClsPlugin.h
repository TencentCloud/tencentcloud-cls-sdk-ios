//
//  baseClsPlugin.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>
#import "ClsConfig.h"

NS_ASSUME_NONNULL_BEGIN

@interface baseClsPlugin : NSObject

- (NSString *) name;
- (BOOL) initWithCLSConfig: (ClsConfig *) config;
@end

NS_ASSUME_NONNULL_END
