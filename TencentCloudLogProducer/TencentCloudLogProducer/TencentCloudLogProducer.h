//
//  TencentCloundLogProducer.h
//  TencentCloundLogProducer
//
//  Created by herrylv on 2022/5/6.
//
#ifndef TencentCloundlogCommon_h
#define TencentCloundlogCommon_h

#import <Foundation/Foundation.h>
#import "ClsLogProducerConfig.h"
#import "TencentCloudLogProducer/ClsLog.h"
#import "ClsTimeUtils.h"

FOUNDATION_EXPORT double TencentCloundLogProducerVersionNumber;


FOUNDATION_EXPORT const unsigned char TencentCloundLogLogProducerVersionString[];



#define CLSLog(fmt, ...) NSLog((@"[CLSiOS] %s " fmt), __FUNCTION__, ##__VA_ARGS__);
#ifdef DEBUG
    #define CLSLogV(fmt, ...) NSLog((@"[CLSiOS] %s:%d: " fmt), __FUNCTION__, __LINE__, ##__VA_ARGS__);
#else
    #define CLSLogV(...);
#endif





#endif /* TencentCloundlogCommon_h */
