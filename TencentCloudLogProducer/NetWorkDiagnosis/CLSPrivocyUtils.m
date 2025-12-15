//
//  CLSPrivocyUtils.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import "CLSPrivocyUtils.h"

@interface CLSPrivocyUtils ()
@property(atomic, assign) BOOL privocy;
@end

@implementation CLSPrivocyUtils
+ (instancetype) sharedInstance {
    static CLSPrivocyUtils * ins = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ins = [[CLSPrivocyUtils alloc] init];
        ins.privocy = NO;
    });
    return ins;
}

- (void)internal_setEnablePrivocy:(BOOL)enablePrivocy {
    self.privocy = enablePrivocy;
}

- (BOOL) internal_isEnablePrivocy {
    return self.privocy;
}

+ (void) setEnablePrivocy: (BOOL) enablePrivocy {
    [[self sharedInstance] internal_setEnablePrivocy:enablePrivocy];
}

+ (BOOL) isEnablePrivocy {
    return [[self sharedInstance] internal_isEnablePrivocy];
}
@end
