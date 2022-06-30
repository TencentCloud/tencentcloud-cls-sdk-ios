//
//  basePlugin.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import <Foundation/Foundation.h>
#import "CLSConfig.h"

NS_ASSUME_NONNULL_BEGIN

@interface basePlugin : NSObject

- (NSString *) name;
- (BOOL) initWithCLSConfig: (CLSConfig *) config;
@end

NS_ASSUME_NONNULL_END
