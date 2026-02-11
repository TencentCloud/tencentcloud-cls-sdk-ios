//
//  CLSCocoa.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import "ClsSystemCapabilities.h"
#if CLS_HAS_UIKIT
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

#import "CLSCocoa.h"
#import "CLSAppUtils.h"
#import "CLSUtdid.h"
#import "CLSDeviceUtils.h"
#import "NSString+CLS.h"
#import "CLSStringUtils.h"
#import "CLSPrivocyUtils.h"
#import "CLSUserInfo.h"


#pragma mark - CLSSpanProviderDelegate
@interface CLSSpanProviderDelegate ()
@property(nonatomic, strong) id<CLSSpanProviderProtocol> spanProvider;
- (CLSResource *) createDefaultResource;
@end

@implementation CLSSpanProviderDelegate

- (instancetype)init {
    self = [super init];
    return self;
}

- (CLSResource *) createDefaultResource {
    BOOL privocy = [CLSPrivocyUtils isEnablePrivocy];
    NSLog(@"🔒 [CLSCocoa] privocy = %d", privocy);
    
    CLSResource *resource = [[CLSResource alloc] init];
    [resource add:@"sdk.language" value:@"Objective-C"];
    
    // device specification, ref: https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/resource/semantic_conventions/device.md
    [resource add:@"device.id" value:[[CLSUtdid getUtdid] copy]];
    [resource add:@"device.model.identifier" value:privocy ? [CLSDeviceUtils getDeviceModelIdentifier] : @""];
    [resource add:@"device.model.name" value:privocy ? [CLSDeviceUtils getDeviceModelIdentifier] : @""];
    [resource add:@"device.manufacturer" value:@"Apple"];
    [resource add:@"device.resolution" value:privocy ? [CLSDeviceUtils getResolution] : @""];
    
#if CLS_HOST_MAC
    [resource add:@"device.brand" value:@"Apple"];
#else
    [resource add:@"device.brand" value:[[[UIDevice currentDevice] model] copy]];
#endif
    
    // os specification, ref: https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/resource/semantic_conventions/os.md
#if CLS_HAS_UIKIT
    NSString *systemName = [[[UIDevice currentDevice] systemName] copy];
    NSString *systemVersion = [[[UIDevice currentDevice] systemVersion] copy];
#else
    NSString *systemName = [[[NSProcessInfo processInfo] operatingSystemName] copy];
    NSString *systemVersion = [[[NSProcessInfo processInfo] operatingSystemVersionString] copy];
#endif
    [resource add:@"os.type" value: @"darwin"];
    [resource add:@"os.description" value: [NSString stringWithFormat:@"%@ %@", systemName, systemVersion]];
    
#if CLS_HOST_MAC
    [resource add:@"os.name" value: @"macOS"];
#elif CLS_HOST_TV
    [resource add:@"os.name" value: @"tvOS"];
#else
    [resource add:@"os.name" value: @"iOS"];
#endif
    [resource add:@"os.version" value: systemVersion];
    [resource add:@"os.root" value: privocy ? [CLSDeviceUtils isJailBreak] : @""];
//        @"os.sdk": [[TelemetryAttributeValue alloc] initWithStringValue:@"iOS"],
    
    // host specification, ref: https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/resource/semantic_conventions/host.md
#if CLS_HOST_MAC
    [resource add:@"host.name" value: @"macOS"];
#elif CLS_HOST_TV
    [resource add:@"host.name" value: @"tvOS"];
#else
    [resource add:@"host.name" value: @"iOS"];
#endif
    [resource add:@"host.type" value: systemName];
    [resource add:@"host.arch" value: privocy ? [CLSDeviceUtils getCPUArch] : @""];
    
    [resource add:@"sdk.language" value: @"Objective-C"];
//    [resource add:@"sdk.name" value: @"tencentcloud-cls-sdk-ios"];
    [resource add:@"cls.sdk.version" value: [CLSStringUtils getSdkVersion]];
    
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *appName = [infoDictionary objectForKey:@"CFBundleDisplayName"];
    if (!appName) {
        appName = [infoDictionary objectForKey:@"CFBundleName"];
    }
    NSString *appVersion = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
    NSString *buildCode = [infoDictionary objectForKey:@"CFBundleVersion"];
    
    [resource add:@"app.version" value:(!appVersion ? @"-" : appVersion)];
    [resource add:@"app.versionCode" value:(!buildCode ? @"-" : buildCode)];
    [resource add:@"app.name" value:(!appName ? @"-" : appName)];
    
    // ========== 网络类型检测（使用系统全局检测） ==========
    NSLog(@"🌐 [CLSCocoa] Using system-based detection");
    NSString *networkType = [CLSDeviceUtils getNetworkTypeName];
    NSString *networkSubType = [CLSDeviceUtils getNetworkSubTypeName];
    NSString *carrier = [CLSDeviceUtils getCarrier];
    // 非真实运营商名或占位符时使用平台标识
    NSString *trimmed = [carrier stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!carrier || carrier.length == 0 ||
        [trimmed isEqualToString:@"Unknown"] ||
        [trimmed isEqualToString:@"无运营商"] ||
        [trimmed isEqualToString:@"-"] ||
        [trimmed isEqualToString:@"--"] ||
        [trimmed isEqualToString:@"占位符"] ||
        [trimmed caseInsensitiveCompare:@"placeholder"] == NSOrderedSame) {
        carrier = @"IOS";
    }
    
    NSLog(@"🌐 [CLSCocoa] networkType = [%@], length=%lu", networkType, (unsigned long)networkType.length);
    NSLog(@"🌐 [CLSCocoa] networkSubType = [%@], length=%lu", networkSubType, (unsigned long)networkSubType.length);
    NSLog(@"📱 [CLSCocoa] carrier = [%@], length=%lu, isNil=%d", carrier, (unsigned long)carrier.length, carrier == nil);
    NSLog(@"🔒 [CLSCocoa] privocy = %d", privocy);
    NSLog(@"✅ [CLSCocoa] Final values: net.access=[%@], net.access_subtype=[%@], carrier=[%@]", 
          privocy ? networkType : @"",
          privocy ? networkSubType : @"",
          privocy ? carrier : @"");
    
    [resource add:@"net.access" value: privocy ? networkType : @""];
    [resource add:@"net.access_subtype" value: privocy ? networkSubType : @""];
    [resource add:@"carrier" value: privocy ? carrier : @""];
    return resource;
}

- (CLSResource *)provideResource {
    return [[self createDefaultResource] copy];
}

- (NSArray<CLSAttribute *> *)provideAttribute{
    NSMutableArray<CLSAttribute*> *attributes =
    (NSMutableArray<CLSAttribute*> *) [CLSAttribute of:
                                           [CLSKeyValue create:@"page.name" value:@""],
                                           nil
    ];
    
    NSArray<CLSAttribute *> *userAttributes = [_spanProvider provideAttribute];
    if (userAttributes) {
        [attributes addObjectsFromArray:userAttributes];
    }
    
    return attributes;
}

- (void) provideUserInfo: (NSMutableArray<CLSAttribute *> *) attributes userinfo: (CLSUserInfo *) info {
    if (info.uid.length > 0) {
        [attributes addObject:[CLSAttribute of:@"user.uid"
                                         value:[info.uid copy]
                              ]
        ];
    }
    
    if (info.channel.length > 0) {
        [attributes addObject:[CLSAttribute of:@"user.channel"
                                         value:[info.channel copy]
                              ]
        ];
    }
    
    if (info.ext) {
        for (NSString *k in info.ext) {
            if (k.length == 0) {
                continue;
            }
            
            [attributes addObject:[CLSAttribute of:[NSString stringWithFormat:@"user.%@", k]
                                             value:[[info.ext valueForKey:k] copy]
                                   ]
            ];
        }
    }
    
}
@end

