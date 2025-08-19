//
//  CLSProtocols.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//


#import <Foundation/Foundation.h>
#import "ClsUtils.h"


@protocol CLSStopDelegate <NSObject>

- (void)stop;

@end

@protocol CLSOutputDelegate <NSObject>

- (void)write:(NSString*)line;

@end

/**
 *    中途取消的状态码
 */
extern const NSInteger kCLSRequestStoped;

