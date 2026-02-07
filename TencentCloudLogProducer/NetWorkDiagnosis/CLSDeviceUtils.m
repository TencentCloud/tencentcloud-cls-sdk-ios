//
//  CLSDeviceUtils.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import "ClsSystemCapabilities.h"
#import "CLSDeviceUtils.h"
#import <sys/utsname.h>

#if CLS_HAS_UIKIT
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

#if CLS_HAS_CORE_TELEPHONY
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#endif


#import <sys/stat.h>
#import <dlfcn.h>
//#import "reachable/Rechable.h"
#import "Reachability.h"
#include <sys/types.h>
#include <sys/sysctl.h>
#include <mach/machine.h>

@interface CLSDeviceUtils ()
+ (NSString *) getNetworkType;
+ (NSString *) getReachabilityStatus;
@end

@implementation CLSDeviceUtils

+ (NSString *) getDeviceModelIdentifier {
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString:systemInfo.machine encoding:NSASCIIStringEncoding];
}

+ (NSString *)getDeviceModel {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSASCIIStringEncoding];
    
    // iPhone
    if ([deviceModel isEqualToString:@"iPhone3,1"])    return @"iPhone 4";
    if ([deviceModel isEqualToString:@"iPhone3,2"])    return @"iPhone 4";
    if ([deviceModel isEqualToString:@"iPhone3,3"])    return @"iPhone 4";
    if ([deviceModel isEqualToString:@"iPhone4,1"])    return @"iPhone 4S";
    if ([deviceModel isEqualToString:@"iPhone5,1"])    return @"iPhone 5";
    if ([deviceModel isEqualToString:@"iPhone5,2"])    return @"iPhone 5 (GSM+CDMA)";
    if ([deviceModel isEqualToString:@"iPhone5,3"])    return @"iPhone 5c (GSM)";
    if ([deviceModel isEqualToString:@"iPhone5,4"])    return @"iPhone 5c (GSM+CDMA)";
    if ([deviceModel isEqualToString:@"iPhone6,1"])    return @"iPhone 5s (GSM)";
    if ([deviceModel isEqualToString:@"iPhone6,2"])    return @"iPhone 5s (GSM+CDMA)";
    if ([deviceModel isEqualToString:@"iPhone7,1"])    return @"iPhone 6 Plus";
    if ([deviceModel isEqualToString:@"iPhone7,2"])    return @"iPhone 6";
    if ([deviceModel isEqualToString:@"iPhone8,1"])    return @"iPhone 6s";
    if ([deviceModel isEqualToString:@"iPhone8,2"])    return @"iPhone 6s Plus";
    if ([deviceModel isEqualToString:@"iPhone8,4"])    return @"iPhone SE";
    if ([deviceModel isEqualToString:@"iPhone9,1"])    return @"iPhone 7";
    if ([deviceModel isEqualToString:@"iPhone9,2"])    return @"iPhone 7 Plus";
    if ([deviceModel isEqualToString:@"iPhone9,3"])    return @"iPhone 7";
    if ([deviceModel isEqualToString:@"iPhone9,4"])    return @"iPhone 7 Plus";
    if ([deviceModel isEqualToString:@"iPhone10,1"])   return @"iPhone_8";
    if ([deviceModel isEqualToString:@"iPhone10,4"])   return @"iPhone_8";
    if ([deviceModel isEqualToString:@"iPhone10,2"])   return @"iPhone_8_Plus";
    if ([deviceModel isEqualToString:@"iPhone10,5"])   return @"iPhone_8_Plus";
    if ([deviceModel isEqualToString:@"iPhone10,3"])   return @"iPhone X";
    if ([deviceModel isEqualToString:@"iPhone10,6"])   return @"iPhone X";
    if ([deviceModel isEqualToString:@"iPhone11,8"])   return @"iPhone XR";
    if ([deviceModel isEqualToString:@"iPhone11,2"])   return @"iPhone XS";
    if ([deviceModel isEqualToString:@"iPhone11,6"])   return @"iPhone XS Max";
    if ([deviceModel isEqualToString:@"iPhone11,4"])   return @"iPhone XS Max";
    if ([deviceModel isEqualToString:@"iPhone12,1"])   return @"iPhone 11";
    if ([deviceModel isEqualToString:@"iPhone12,3"])   return @"iPhone 11 Pro";
    if ([deviceModel isEqualToString:@"iPhone12,5"])   return @"iPhone 11 Pro Max";
    if ([deviceModel isEqualToString:@"iPhone12,8"])   return @"iPhone SE2";
    if ([deviceModel isEqualToString:@"iPhone13,1"])   return @"iPhone 12 mini";
    if ([deviceModel isEqualToString:@"iPhone13,2"])   return @"iPhone 12";
    if ([deviceModel isEqualToString:@"iPhone13,3"])   return @"iPhone 12 Pro";
    if ([deviceModel isEqualToString:@"iPhone13,4"])   return @"iPhone 12 Pro Max";
    if ([deviceModel isEqualToString:@"iPhone14,4"])   return @"iPhone 13 mini";
    if ([deviceModel isEqualToString:@"iPhone14,5"])   return @"iPhone 13";
    if ([deviceModel isEqualToString:@"iPhone14,2"])   return @"iPhone 13 Pro";
    if ([deviceModel isEqualToString:@"iPhone14,3"])   return @"iPhone 13 Pro Max";
    
    // iPod Touch
    if ([deviceModel isEqualToString:@"iPod1,1"])      return @"iPod Touch 1G";
    if ([deviceModel isEqualToString:@"iPod2,1"])      return @"iPod Touch 2G";
    if ([deviceModel isEqualToString:@"iPod3,1"])      return @"iPod Touch 3G";
    if ([deviceModel isEqualToString:@"iPod4,1"])      return @"iPod Touch 4G";
    if ([deviceModel isEqualToString:@"iPod5,1"])      return @"iPod Touch (5 Gen)";
    if ([deviceModel isEqualToString:@"iPod7,1"])      return @"iPod Touch (6 Gen)";
    
    // iPad
    if ([deviceModel isEqualToString:@"iPad1,1"])      return @"iPad";
    if ([deviceModel isEqualToString:@"iPad1,2"])      return @"iPad 3G";
    if ([deviceModel isEqualToString:@"iPad2,1"])      return @"iPad 2 (WiFi)";
    if ([deviceModel isEqualToString:@"iPad2,2"])      return @"iPad 2";
    if ([deviceModel isEqualToString:@"iPad2,3"])      return @"iPad 2 (CDMA)";
    if ([deviceModel isEqualToString:@"iPad2,4"])      return @"iPad 2";
    if ([deviceModel isEqualToString:@"iPad3,1"])      return @"iPad 3 (WiFi)";
    if ([deviceModel isEqualToString:@"iPad3,2"])      return @"iPad 3 (GSM+CDMA)";
    if ([deviceModel isEqualToString:@"iPad3,3"])      return @"iPad 3";
    if ([deviceModel isEqualToString:@"iPad3,4"])      return @"iPad 4 (WiFi)";
    if ([deviceModel isEqualToString:@"iPad3,5"])      return @"iPad 4";
    if ([deviceModel isEqualToString:@"iPad3,6"])      return @"iPad 4 (GSM+CDMA)";
    if ([deviceModel isEqualToString:@"iPad6,11"])      return @"iPad 5";
    if ([deviceModel isEqualToString:@"iPad6,12"])      return @"iPad 5";
    if ([deviceModel isEqualToString:@"iPad7,5"])      return @"iPad 6";
    if ([deviceModel isEqualToString:@"iPad7,6"])      return @"iPad 6";
    if ([deviceModel isEqualToString:@"iPad7,11"])      return @"iPad 7";
    if ([deviceModel isEqualToString:@"iPad7,12"])      return @"iPad 7";
    if ([deviceModel isEqualToString:@"iPad11,6"])      return @"iPad 8";
    if ([deviceModel isEqualToString:@"iPad11,6"])      return @"iPad 8";
    if ([deviceModel isEqualToString:@"iPad12,1"])      return @"iPad 9";
    if ([deviceModel isEqualToString:@"iPad12,2"])      return @"iPad 9";
    
    // iPad Air
    if ([deviceModel isEqualToString:@"iPad4,1"])      return @"iPad Air (WiFi)";
    if ([deviceModel isEqualToString:@"iPad4,2"])      return @"iPad Air (Cellular)";
    if ([deviceModel isEqualToString:@"iPad5,3"])      return @"iPad Air 2";
    if ([deviceModel isEqualToString:@"iPad5,4"])      return @"iPad Air 2";
    if ([deviceModel isEqualToString:@"iPad11,3"])      return @"iPad Air 3";
    if ([deviceModel isEqualToString:@"iPad11,4"])      return @"iPad Air 3";
    if ([deviceModel isEqualToString:@"iPad13,1"])      return @"iPad Air 4";
    if ([deviceModel isEqualToString:@"iPad13,2"])      return @"iPad Air 4";
    
    // iPad Mini
    if ([deviceModel isEqualToString:@"iPad2,5"])      return @"iPad Mini (WiFi)";
    if ([deviceModel isEqualToString:@"iPad2,6"])      return @"iPad Mini";
    if ([deviceModel isEqualToString:@"iPad2,7"])      return @"iPad Mini (GSM+CDMA)";
    if ([deviceModel isEqualToString:@"iPad4,4"])      return @"iPad Mini 2 (WiFi)";
    if ([deviceModel isEqualToString:@"iPad4,5"])      return @"iPad Mini 2 (Cellular)";
    if ([deviceModel isEqualToString:@"iPad4,6"])      return @"iPad Mini 2";
    if ([deviceModel isEqualToString:@"iPad4,7"])      return @"iPad Mini 3";
    if ([deviceModel isEqualToString:@"iPad4,8"])      return @"iPad Mini 3";
    if ([deviceModel isEqualToString:@"iPad4,9"])      return @"iPad Mini 3";
    if ([deviceModel isEqualToString:@"iPad5,1"])      return @"iPad Mini 4 (WiFi)";
    if ([deviceModel isEqualToString:@"iPad5,2"])      return @"iPad Mini 4 (LTE)";
    if ([deviceModel isEqualToString:@"iPad11,1"])      return @"iPad Mini 5";
    if ([deviceModel isEqualToString:@"iPad11,2"])      return @"iPad Mini 5";
    if ([deviceModel isEqualToString:@"iPad14,1"])      return @"iPad Mini 6";
    if ([deviceModel isEqualToString:@"iPad14,2"])      return @"iPad Mini 6";

    // iPad Pro
    if ([deviceModel isEqualToString:@"iPad6,3"])      return @"iPad Pro 9.7";
    if ([deviceModel isEqualToString:@"iPad6,4"])      return @"iPad Pro 9.7";
    if ([deviceModel isEqualToString:@"iPad7,3"])      return @"iPad Pro 10.5";
    if ([deviceModel isEqualToString:@"iPad7,4"])      return @"iPad Pro 10.5";
    if ([deviceModel isEqualToString:@"iPad8,1"])      return @"iPad Pro 11";
    if ([deviceModel isEqualToString:@"iPad8,2"])      return @"iPad Pro 11";
    if ([deviceModel isEqualToString:@"iPad8,3"])      return @"iPad Pro 11";
    if ([deviceModel isEqualToString:@"iPad8,4"])      return @"iPad Pro 11";
    if ([deviceModel isEqualToString:@"iPad8,9"])      return @"iPad Pro 11 2";
    if ([deviceModel isEqualToString:@"iPad8,10"])      return @"iPad Pro 11 2";
    if ([deviceModel isEqualToString:@"iPad13,4"])      return @"iPad Pro 11 3";
    if ([deviceModel isEqualToString:@"iPad13,5"])      return @"iPad Pro 11 3";
    if ([deviceModel isEqualToString:@"iPad13,6"])      return @"iPad Pro 11 3";
    if ([deviceModel isEqualToString:@"iPad13,7"])      return @"iPad Pro 11 3";
    if ([deviceModel isEqualToString:@"iPad6,7"])      return @"iPad Pro 12.9";
    if ([deviceModel isEqualToString:@"iPad6,8"])      return @"iPad Pro 12.9";
    if ([deviceModel isEqualToString:@"iPad7,1"])      return @"iPad Pro 12.9 2";
    if ([deviceModel isEqualToString:@"iPad7,2"])      return @"iPad Pro 12.9 2";
    if ([deviceModel isEqualToString:@"iPad8,5"])      return @"iPad Pro 12.9 3";
    if ([deviceModel isEqualToString:@"iPad8,6"])      return @"iPad Pro 12.9 3";
    if ([deviceModel isEqualToString:@"iPad8,7"])      return @"iPad Pro 12.9 3";
    if ([deviceModel isEqualToString:@"iPad8,8"])      return @"iPad Pro 12.9 3";
    if ([deviceModel isEqualToString:@"iPad8,11"])      return @"iPad Pro 12.9 4";
    if ([deviceModel isEqualToString:@"iPad8,12"])      return @"iPad Pro 12.9 4";
    if ([deviceModel isEqualToString:@"iPad13,8"])      return @"iPad Pro 12.9 5";
    if ([deviceModel isEqualToString:@"iPad13,9"])      return @"iPad Pro 12.9 5";
    if ([deviceModel isEqualToString:@"iPad13,10"])      return @"iPad Pro 12.9 5";
    if ([deviceModel isEqualToString:@"iPad13,11"])      return @"iPad Pro 12.9 5";
    
    // Apple TV
    if ([deviceModel isEqualToString:@"AppleTV1,1"])      return @"Apple TV 1";
    if ([deviceModel isEqualToString:@"AppleTV2,1"])      return @"Apple TV 2";
    if ([deviceModel isEqualToString:@"AppleTV3,1"])      return @"Apple TV 3";
    if ([deviceModel isEqualToString:@"AppleTV3,2"])      return @"Apple TV 3";
    if ([deviceModel isEqualToString:@"AppleTV5,3"])      return @"Apple TV 4";
    if ([deviceModel isEqualToString:@"AppleTV6,2"])      return @"Apple TV 4K";
    if ([deviceModel isEqualToString:@"AppleTV11,1"])      return @"Apple TV 4K 2";
    
    // Simulator
    if ([deviceModel isEqualToString:@"i386"])         return @"Simulator";
    if ([deviceModel isEqualToString:@"x86_64"])       return @"Simulator";
    
    return deviceModel;
}


+ (NSString *) isJailBreak
{
    //以下检测的过程是越往下，越狱越高级
    //获取越狱文件路径
    NSString *cydiaPath = @"/Applications/Cydia.app";
    NSString *aptPath = @"/private/var/lib/apt/";
    if ([[NSFileManager defaultManager] fileExistsAtPath:cydiaPath]) {
        return @"true";
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:aptPath]) {
        return @"true";
    }
    
    //可能存在hook了NSFileManager方法，此处用底层C stat去检测
    struct stat stat_info;
    if (0 == stat("/Library/MobileSubstrate/MobileSubstrate.dylib", &stat_info)) {
        return @"true";
    }
    if (0 == stat("/Applications/Cydia.app", &stat_info)) {
        return @"true";
    }
    if (0 == stat("/var/lib/cydia/", &stat_info)) {
        return @"true";
    }
    if (0 == stat("/var/cache/apt", &stat_info)) {
        return @"true";
    }
    
    //可能存在stat也被hook了，可以看stat是不是出自系统库，有没有被攻击者换掉。这种情况出现的可能性很小
    int ret;
    Dl_info dylib_info;
    int (*func_stat)(const char *,struct stat *) = stat;
    if ((ret = dladdr(func_stat, &dylib_info))) {
        //相等为0，不相等，肯定被攻击
        if (strcmp(dylib_info.dli_fname, "/usr/lib/system/libsystem_kernel.dylib")) {
            return @"true";
        }
    }
    
    //通常，越狱机的输出结果会包含字符串：Library/MobileSubstrate/MobileSubstrate.dylib。
    //攻击者给MobileSubstrate改名，原理都是通过DYLD_INSERT_LIBRARIES注入动态库。那么可以检测当前程序运行的环境变量
    char *env = getenv("DYLD_INSERT_LIBRARIES");
    if (env != NULL) {
        return @"true";
    }
    
    return @"false";
}

+ (NSString *)getResolution {
#if CLS_HAS_UIKIT
    CGSize size = [[UIScreen mainScreen] bounds].size;
    CGFloat scale = [[UIScreen mainScreen] scale];
    return [NSString stringWithFormat:@"%.0f*%.0f",size.height * scale, size.width * scale];
#else
    NSScreen *screen = [NSScreen mainScreen];
    NSDictionary *description = [screen deviceDescription];
    NSSize size = [[description objectForKey:NSDeviceSize] sizeValue];
    return [NSString stringWithFormat:@"%.0f*%.0f",size.height, size.width];
#endif
}

+ (NSString *)getCarrier {
#if CLS_HAS_CORE_TELEPHONY
#if TARGET_IPHONE_SIMULATOR
    return @"Unknown";
#endif
    @try {
        CTTelephonyNetworkInfo *info = [[CTTelephonyNetworkInfo alloc] init];
        CTCarrier *carrier = nil;
        if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 12.1) {
            if ([info respondsToSelector:@selector(serviceSubscriberCellularProviders)]) {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wunguarded-availability-new"
                carrier = info.serviceSubscriberCellularProviders[info.serviceSubscriberCellularProviders.allKeys.firstObject];
                if (nil != carrier && nil != carrier.mobileNetworkCode) {
                    carrier = info.serviceSubscriberCellularProviders[info.serviceSubscriberCellularProviders.allKeys.lastObject];
                }
    #pragma clang diagnostic pop
            }
        }
        if(carrier == nil) {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            carrier = info.subscriberCellularProvider;
    #pragma clang diagnostic pop
        }
        if (carrier != nil) {
            if (!carrier.isoCountryCode) {
                return @"无运营商";
            } else {
                return [carrier carrierName];
            }
        } else {
            return @"Unknown";
        }
    } @catch (NSException *exception) {
        return @"Unknown";
    }
    
#else
    return @"Unknown";
#endif
}

+ (NSString *)getReachabilityStatus {
    Reachability *reachability = [Reachability reachabilityWithHostname:@"cloud.tencent.com"];
    switch ([reachability currentReachabilityStatus]) {
        case NotReachable:
            return @"Unknown";
        case ReachableViaWiFi:
            return @"Wi-Fi";
            break;
        case ReachableViaWWAN:
            return @"Cellular";
            break;
        default:
            return @"";
    }
}

+ (NSString *)getNetworkType {
#if CLS_HAS_CORE_TELEPHONY
    @try {
        CTTelephonyNetworkInfo *networkInfo = [[CTTelephonyNetworkInfo alloc] init];
        NSString *currentStatus = networkInfo.currentRadioAccessTechnology;
        return currentStatus;
    } @catch (NSException *exception) {
        return @"Unknown";
    }
#else
    return @"Unknown";
#endif
}

+ (NSString *)getNetworkTypeName {
#if CLS_HAS_CORE_TELEPHONY
    NSString *currentReachabilityStatus = [self getReachabilityStatus];
    if(![@"Cellular" isEqual:currentReachabilityStatus]) {
        return currentReachabilityStatus;
    }
    
    NSString *currentStatus = [self getNetworkType];

    if ([currentStatus isEqualToString:CTRadioAccessTechnologyLTE]) {
        return @"4G";
    }

    if (@available(iOS 14.1, *)) {
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyNRNSA]
            || [currentStatus isEqualToString:CTRadioAccessTechnologyNR]) {
            return @"5G";
        }
    }
    
    if ([currentStatus isEqualToString:CTRadioAccessTechnologyWCDMA]
       || [currentStatus isEqualToString:CTRadioAccessTechnologyHSDPA]
       || [currentStatus isEqualToString:CTRadioAccessTechnologyHSUPA]
       || [currentStatus isEqualToString:CTRadioAccessTechnologyCDMAEVDORev0]
       || [currentStatus isEqualToString:CTRadioAccessTechnologyCDMAEVDORevA]
       || [currentStatus isEqualToString:CTRadioAccessTechnologyCDMAEVDORevB]
       || [currentStatus isEqualToString:CTRadioAccessTechnologyeHRPD]) {
        return @"3G";
    }
    
    if ([currentStatus isEqualToString:CTRadioAccessTechnologyGPRS]
        || [currentStatus isEqualToString:CTRadioAccessTechnologyEdge]
        || [currentStatus isEqualToString:CTRadioAccessTechnologyCDMA1x]) {
        return @"2G";
    }
    
    return @"Unknown";
#else
    return @"Unknown";
#endif
}

+ (NSString *)getNetworkSubTypeName {
#if CLS_HAS_CORE_TELEPHONY
    NSString *currentReachabilityStatus = [self getReachabilityStatus];
    if(![@"Cellular" isEqual:currentReachabilityStatus]) {
        return @"Unknown";
    }
    
    NSString *currentStatus = [self getNetworkType];
    
    if ([currentStatus isEqualToString:CTRadioAccessTechnologyGPRS]) {
        return @"GPRS";
    }
    
    if ([currentStatus isEqualToString:CTRadioAccessTechnologyEdge]) {
        return @"EDGE";
    }
    
    if ([currentStatus isEqualToString:CTRadioAccessTechnologyWCDMA]) {
        return @"WCDMA";
    }
    
    if ([currentStatus isEqualToString:CTRadioAccessTechnologyHSDPA]) {
        return @"HSDPA";
    }
    
    if ([currentStatus isEqualToString:CTRadioAccessTechnologyHSUPA]) {
        return @"HSUPA";
    }
    
    if ([currentStatus isEqualToString:CTRadioAccessTechnologyCDMA1x]) {
        return @"CDMA1x";
    }
    
    if ([currentStatus isEqualToString:CTRadioAccessTechnologyCDMAEVDORev0]) {
        return @"EVDOv0";
    }
    
    if ([currentStatus isEqualToString:CTRadioAccessTechnologyCDMAEVDORevA]) {
        return @"EVDORevA";
    }
    
    if ([currentStatus isEqualToString:CTRadioAccessTechnologyCDMAEVDORevB]) {
        return @"EVDORevB";
    }
    
    if ([currentStatus isEqualToString:CTRadioAccessTechnologyeHRPD]) {
        return @"HRPD";
    }
    
    if ([currentStatus isEqualToString:CTRadioAccessTechnologyLTE]) {
        return @"LTE";
    }
    
    if (@available(iOS 14.1, *)) {
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyNRNSA]) {
            return @"NRNSA";
        } else if ([currentStatus isEqualToString:CTRadioAccessTechnologyNR]) {
            return @"NR";
        }
    }
    
    return @"Unknown";
#else
    return @"Unknown";
#endif
}

+ (NSString *) getCPUArch {
    NSMutableString *cpu = [[NSMutableString alloc] init];
    size_t size;
    cpu_type_t type;
    cpu_subtype_t subtype;
    size = sizeof(type);
    sysctlbyname("hw.cputype", &type, &size, NULL, 0);

    size = sizeof(subtype);
    sysctlbyname("hw.cpusubtype", &subtype, &size, NULL, 0);

    if (type == CPU_TYPE_X86_64) {
        [cpu appendString:@"x86_64"];
    } else if (type == CPU_TYPE_X86) {
        [cpu appendString:@"x86"];
    } else if (type == CPU_TYPE_ARM) {
        [cpu appendString:@"ARM"];
        switch (subtype) {
            case CPU_SUBTYPE_ARM_V6:
                [cpu appendString:@"v6"];
                break;
            case CPU_SUBTYPE_ARM_V7:
                [cpu appendString:@"v7"];
                break;
            case CPU_SUBTYPE_ARM_V8:
                [cpu appendString:@"v8"];
                break;
            default:
                break;
        }
    } else if (type == CPU_TYPE_ARM64) {
        [cpu appendString:@"ARM64"];
    }
    return [cpu copy];
}

// MARK: - Interface-Based Network Detection (for Probing Scenarios)

/// 根据接口名称判断是否为蜂窝网络接口
+ (BOOL)isCellularInterface:(NSString *)interfaceName {
    if (!interfaceName || interfaceName.length == 0) {
        return NO;
    }
    // 蜂窝网络接口命名规则：pdp_ip0, pdp_ip1, pdp_ip2...
    return [interfaceName hasPrefix:@"pdp_ip"];
}

/// 根据接口名称判断是否为 Wi-Fi 接口
+ (BOOL)isWiFiInterface:(NSString *)interfaceName {
    if (!interfaceName || interfaceName.length == 0) {
        return NO;
    }
    // Wi-Fi 接口命名规则：en0, en1...
    return [interfaceName hasPrefix:@"en"];
}

/// 根据接口名称获取网络类型（用于探测场景）
/// @param interfaceName 网络接口名称（如 "pdp_ip0", "en0"）
/// @return 网络类型名称（"Wi-Fi", "4G", "5G", "3G", "2G", "Unknown"）
+ (NSString *)getNetworkTypeNameForInterface:(NSString *)interfaceName {
    NSLog(@"🔍 [getNetworkTypeNameForInterface] interfaceName = [%@]", interfaceName);
    
    // 1. 如果未提供接口名称，降级到系统全局检测
    if (!interfaceName || interfaceName.length == 0) {
        NSLog(@"⚠️ [getNetworkTypeNameForInterface] No interface name, fallback to system detection");
        return [self getNetworkTypeName];
    }
    
    // 2. 判断接口类型
    if ([self isWiFiInterface:interfaceName]) {
        // Wi-Fi 接口
        NSLog(@"✅ [getNetworkTypeNameForInterface] Wi-Fi interface detected: %@", interfaceName);
        return @"Wi-Fi";
    }
    
    if ([self isCellularInterface:interfaceName]) {
        // 蜂窝网络接口 - 需要进一步检测具体类型（4G/5G/3G/2G）
        NSLog(@"✅ [getNetworkTypeNameForInterface] Cellular interface detected: %@", interfaceName);
        
#if CLS_HAS_CORE_TELEPHONY
        NSString *currentStatus = [self getNetworkType];
        NSLog(@"📶 [getNetworkTypeNameForInterface] Radio technology: %@", currentStatus);
        
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyLTE]) {
            return @"4G";
        }
        
        if (@available(iOS 14.1, *)) {
            if ([currentStatus isEqualToString:CTRadioAccessTechnologyNRNSA]
                || [currentStatus isEqualToString:CTRadioAccessTechnologyNR]) {
                return @"5G";
            }
        }
        
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyWCDMA]
           || [currentStatus isEqualToString:CTRadioAccessTechnologyHSDPA]
           || [currentStatus isEqualToString:CTRadioAccessTechnologyHSUPA]
           || [currentStatus isEqualToString:CTRadioAccessTechnologyCDMAEVDORev0]
           || [currentStatus isEqualToString:CTRadioAccessTechnologyCDMAEVDORevA]
           || [currentStatus isEqualToString:CTRadioAccessTechnologyCDMAEVDORevB]
           || [currentStatus isEqualToString:CTRadioAccessTechnologyeHRPD]) {
            return @"3G";
        }
        
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyGPRS]
            || [currentStatus isEqualToString:CTRadioAccessTechnologyEdge]
            || [currentStatus isEqualToString:CTRadioAccessTechnologyCDMA1x]) {
            return @"2G";
        }
        
        // 无法识别的蜂窝网络类型
        NSLog(@"⚠️ [getNetworkTypeNameForInterface] Unknown cellular type: %@", currentStatus);
        return @"Cellular";
#else
        return @"Cellular";
#endif
    }
    
    // 3. 其他接口（回环、VPN、桥接等）
    NSLog(@"⚠️ [getNetworkTypeNameForInterface] Other interface type: %@", interfaceName);
    return @"Unknown";
}

/// 根据接口名称获取网络子类型（用于探测场景）
/// @param interfaceName 网络接口名称（如 "pdp_ip0", "en0"）
/// @return 网络子类型名称（"LTE", "NRNSA", "NR", "WCDMA", etc.）
+ (NSString *)getNetworkSubTypeNameForInterface:(NSString *)interfaceName {
    NSLog(@"🔍 [getNetworkSubTypeNameForInterface] interfaceName = [%@]", interfaceName);
    
    // 1. 如果未提供接口名称，降级到系统全局检测
    if (!interfaceName || interfaceName.length == 0) {
        NSLog(@"⚠️ [getNetworkSubTypeNameForInterface] No interface name, fallback to system detection");
        return [self getNetworkSubTypeName];
    }
    
    // 2. Wi-Fi 接口 - 返回 Unknown（Wi-Fi 没有子类型）
    if ([self isWiFiInterface:interfaceName]) {
        NSLog(@"✅ [getNetworkSubTypeNameForInterface] Wi-Fi interface, returning 'Unknown'");
        return @"Unknown";
    }
    
    // 3. 蜂窝网络接口 - 检测具体的无线技术
    if ([self isCellularInterface:interfaceName]) {
        NSLog(@"✅ [getNetworkSubTypeNameForInterface] Cellular interface: %@", interfaceName);
        
#if CLS_HAS_CORE_TELEPHONY
        NSString *currentStatus = [self getNetworkType];
        NSLog(@"📶 [getNetworkSubTypeNameForInterface] Radio technology: %@", currentStatus);
        
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyGPRS]) {
            return @"GPRS";
        }
        
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyEdge]) {
            return @"EDGE";
        }
        
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyWCDMA]) {
            return @"WCDMA";
        }
        
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyHSDPA]) {
            return @"HSDPA";
        }
        
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyHSUPA]) {
            return @"HSUPA";
        }
        
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyCDMA1x]) {
            return @"CDMA1x";
        }
        
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyCDMAEVDORev0]) {
            return @"EVDOv0";
        }
        
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyCDMAEVDORevA]) {
            return @"EVDORevA";
        }
        
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyCDMAEVDORevB]) {
            return @"EVDORevB";
        }
        
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyeHRPD]) {
            return @"HRPD";
        }
        
        if ([currentStatus isEqualToString:CTRadioAccessTechnologyLTE]) {
            return @"LTE";
        }
        
        if (@available(iOS 14.1, *)) {
            if ([currentStatus isEqualToString:CTRadioAccessTechnologyNRNSA]) {
                return @"NRNSA";
            } else if ([currentStatus isEqualToString:CTRadioAccessTechnologyNR]) {
                return @"NR";
            }
        }
        
        // 无法识别的蜂窝网络子类型
        NSLog(@"⚠️ [getNetworkSubTypeNameForInterface] Unknown cellular subtype: %@", currentStatus);
        return @"Unknown";
#else
        return @"Unknown";
#endif
    }
    
    // 4. 其他接口
    NSLog(@"⚠️ [getNetworkSubTypeNameForInterface] Other interface type: %@", interfaceName);
    return @"Unknown";
}

@end

