//
//  TencentCloundLogProducer.h
//  TencentCloundLogProducer
//
//  Created by herrylv on 2022/5/6.
//

#import <Foundation/Foundation.h>


FOUNDATION_EXPORT double TencentCloundLogProducerVersionNumber;


FOUNDATION_EXPORT const unsigned char TencentCloundLogLogProducerVersionString[];

#ifndef TencentCloundlogCommon_h
#define TencentCloundlogCommon_h

#define CLSLog(fmt, ...) NSLog((@"[CLSiOS] %s " fmt), __FUNCTION__, ##__VA_ARGS__);
#ifdef DEBUG
    #define CLSLogV(fmt, ...) NSLog((@"[CLSiOS] %s:%d: " fmt), __FUNCTION__, __LINE__, ##__VA_ARGS__);
#else
    #define CLSLogV(...);
#endif

#endif /* TencentCloundlogCommon_h */


#import "LogProducerClient.h"
#import "LogProducerConfig.h"
#import "Log.h"
#import "TimeUtils.h"

