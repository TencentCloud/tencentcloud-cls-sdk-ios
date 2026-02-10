//
//  CLSSpanProviderProtocol.h
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import <Foundation/Foundation.h>
#import "CLSSpan.h"

NS_ASSUME_NONNULL_BEGIN

@protocol CLSSpanProviderProtocol <NSObject>

- (CLSResource *) provideResource;

- (NSArray<CLSAttribute *> *) provideAttribute;

@end

NS_ASSUME_NONNULL_END
