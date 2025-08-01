

#import <Foundation/Foundation.h>
#import "Log.h"
#import "TimeUtils.h"

@interface Log ()

@end

@implementation Log

- (id) init
{
    if (self = [super init])
    {
        self->logTime = 0;
        self->content = [NSMutableDictionary dictionary];

    }

    return self;
}

- (void)PutContent:(NSString *) key value:(NSString *)value
{
    if (key && value) {
        [self->content setObject:value forKey:key];
    }
}

- (NSMutableDictionary *)getContent
{
    return self->content;
}

- (void)SetTime:(int64_t) logTime
{
    self->logTime = logTime;
}

- (int64_t)getTime
{
    return self->logTime;
}

@end
