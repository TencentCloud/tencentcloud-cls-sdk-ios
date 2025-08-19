

#import <Foundation/Foundation.h>
#import "TencentCloudLogProducer/ClsLog.h"
#import "ClsTimeUtils.h"

@interface ClsLog ()

@end

@implementation ClsLog

- (id) init
{
    if (self = [super init])
    {
        self->logTime = 0;
        self->content = [NSMutableDictionary dictionary];

    }

    return self;
}

- (void)PutClsContent:(NSString *) key value:(NSString *)value
{
    if (key && value) {
        [self->content setObject:value forKey:key];
    }
}

- (NSMutableDictionary *)getClsContent
{
    return self->content;
}

- (void)SetClsTime:(int64_t) time
{
    self->logTime = time;
}

- (unsigned int)getClsTime
{
    return self->logTime;
}

@end
