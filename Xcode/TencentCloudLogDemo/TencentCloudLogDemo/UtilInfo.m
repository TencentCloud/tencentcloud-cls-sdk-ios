
#import "UtilInfo.h"

@implementation DemoUtils

+ (instancetype)sharedInstance {
    static DemoUtils * ins = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ins = [[DemoUtils alloc] init];
    });
    return ins;
}
@end
