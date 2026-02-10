//
//  CLSIdGenerator.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import "CLSIdGenerator.h"
#include <stdlib.h>
#import <limits.h>

static const long INVALID_ID = 0;

@implementation CLSIdGenerator

+ (NSString *) generateTraceId {
    int idHi = 0;
    int idLo = 0;
    do {
        idHi = arc4random_uniform(INT_MAX);
        idLo = arc4random_uniform(INT_MAX);
    } while( idHi == INVALID_ID || idLo == INVALID_ID);
    
    return [NSString stringWithFormat:@"%016d%016d", idHi, idLo];
}

@end
