

#import "TimeUtils.h"
#import "LogProducerConfig.h"
#import <sys/sysctl.h>

@interface TimeUtils ()
+(NSTimeInterval) elapsedRealtime;

@end

static NSInteger serverTime = 0;
static NSTimeInterval elapsedRealtime = 0;

@implementation TimeUtils
+(NSInteger) getTimeInMilliis
{
    if( 0L == elapsedRealtime) {
        NSInteger time = [[NSDate date] timeIntervalSince1970];
        return time;
    }
    
    NSInteger delta = [self elapsedRealtime] - elapsedRealtime;
    
    return serverTime + delta;
}

+ (NSTimeInterval)elapsedRealtime {
    struct timeval boottime;
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    size_t size = sizeof(boottime);

    struct timeval now;
    struct timezone tz;
    gettimeofday(&now, &tz);

    double uptime = -1;

    if (sysctl(mib, 2, &boottime, &size, NULL, 0) != -1 && boottime.tv_sec != 0)
    {
        uptime = now.tv_sec - boottime.tv_sec;
        uptime += (double)(now.tv_usec - boottime.tv_usec) / 1000000.0;
        return uptime;
    }
    
    return [[NSProcessInfo processInfo] systemUptime];
}
@end
