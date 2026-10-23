#import "ClsLogModel.h"
#import <stdatomic.h>

const uint64_t kCLSMaxSingleLogBytes = 512 * 1024;

static atomic_bool gCLSLogEnabled = ATOMIC_VAR_INIT(false);

BOOL CLSLogIsEnabled(void) {
    return atomic_load(&gCLSLogEnabled);
}

void CLSSetLogEnabled(BOOL enabled) {
    atomic_store(&gCLSLogEnabled, enabled ? true : false);
}

NSString *CLSMask(NSString * _Nullable value) {
    if (value == nil || value.length == 0) {
        return @"(nil)";
    }
    NSUInteger len = value.length;
    if (len <= 4) {
        return [NSString stringWithFormat:@"***(len=%lu)", (unsigned long)len];
    }
    NSString *prefix = [value substringToIndex:2];
    NSString *suffix = [value substringFromIndex:len - 2];
    return [NSString stringWithFormat:@"%@***%@(len=%lu)", prefix, suffix, (unsigned long)len];
}
