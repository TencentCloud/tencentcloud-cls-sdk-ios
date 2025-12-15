//
//  CLSUtdid.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import "CLSUtdid.h"
#import "CLSStorage.h"

@interface CLSUtdid ()

@end

@implementation CLSUtdid
+ (NSString *) getUtdid {
    NSString *utdid = [CLSStorage getUtdid];
    if(utdid.length > 0) {
        return [utdid copy];
    }
    
    NSString *uuid = [[NSUUID UUID] UUIDString];
    [CLSStorage setUtdid:uuid];
    
    return [uuid copy];
}

+ (void) setUtdid: (NSString *) utdid {
    if (utdid.length == 0) {
        return;
    }
    
    [CLSStorage setUtdid:utdid];
}

@end
