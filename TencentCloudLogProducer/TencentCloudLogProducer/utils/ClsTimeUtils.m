

#import "ClsTimeUtils.h"
#import "ClsLogProducerConfig.h"
#import <sys/sysctl.h>

@interface ClsTimeUtils ()
+(NSTimeInterval) elapsedClsRealtime;

@end

static NSInteger serverTime = 0;
static NSTimeInterval elapsedClsRealtime = 0;

@implementation ClsTimeUtils
+(NSInteger) getClsTimeInMilliis
{
    if( 0L == elapsedClsRealtime) {
        NSInteger time = [[NSDate date] timeIntervalSince1970];
        return time;
    }
    
    NSInteger delta = [self elapsedClsRealtime] - elapsedClsRealtime;
    
    return serverTime + delta;
}

+ (NSTimeInterval)elapsedClsRealtime {
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
