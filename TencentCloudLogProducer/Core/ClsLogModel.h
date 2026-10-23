#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const uint64_t kCLSMaxSingleLogBytes;

FOUNDATION_EXPORT BOOL CLSLogIsEnabled(void);

FOUNDATION_EXPORT void CLSSetLogEnabled(BOOL enabled);

FOUNDATION_EXPORT NSString *CLSMask(NSString * _Nullable value);

#define CLSLog(fmt, ...) \
    do { if (CLSLogIsEnabled()) NSLog((@"[CLS] " fmt), ##__VA_ARGS__); } while (0)

NS_ASSUME_NONNULL_END
