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
@property(nonatomic, strong) CLSExtraProvider *extraProvider;
- (void) provideExtra: (NSMutableArray<CLSAttribute *> *)attributes;
- (CLSResource *) createDefaultResource;
@end

@implementation CLSSpanProviderDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _extraProvider = [[CLSExtraProvider alloc] init];
    }
    return self;
}

- (instancetype)initWithExtraProvider:(CLSExtraProvider *)extraProvider {
    self = [super init];
    if (self) {
        _extraProvider = extraProvider ?: [[CLSExtraProvider alloc] init];
    }
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
    
    // ========== 网络类型检测（支持接口名称传递） ==========
    NSString *networkType = nil;
    NSString *networkSubType = nil;
    
    // 1. 尝试从 extras 中获取接口名称（探测场景）
    NSDictionary *extras = [_extraProvider getExtras];
    NSString *interfaceName = extras[@"network.interface.name"];
    
    if (interfaceName && interfaceName.length > 0) {
        // 探测场景：使用指定的网络接口
        NSLog(@"🔍 [CLSCocoa] Using interface-based detection: %@", interfaceName);
        networkType = [CLSDeviceUtils getNetworkTypeNameForInterface:interfaceName];
        networkSubType = [CLSDeviceUtils getNetworkSubTypeNameForInterface:interfaceName];
    } else {
        // 常规场景：使用系统全局检测
        NSLog(@"🌐 [CLSCocoa] Using system-based detection");
        networkType = [CLSDeviceUtils getNetworkTypeName];
        networkSubType = [CLSDeviceUtils getNetworkSubTypeName];
    }
    
    NSString *carrier = [CLSDeviceUtils getCarrier];
    
    NSLog(@"🌐 [CLSCocoa] interfaceName = [%@]", interfaceName ?: @"(nil)");
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
    
    [self provideExtra:attributes];
    
    NSArray<CLSAttribute *> *userAttributes = [_spanProvider provideAttribute];
    if (userAttributes) {
        [attributes addObjectsFromArray:userAttributes];
    }
    
    return attributes;
}

- (void) provideExtra: (NSMutableArray<CLSAttribute *> *)attributes {
    NSDictionary<NSString *, NSString *> *extras = [_extraProvider getExtras];
    if (!extras) {
        return;
    }
    
    for (NSString *k in extras) {
        NSString *key = [NSString stringWithFormat:@"extras.%@", k];
        if ([[extras valueForKey:k] isKindOfClass:[NSDictionary<NSString *, NSString *> class]]) {
            [attributes addObject:[CLSAttribute of:key
                                             value:[NSString stringWithDictionary:(NSDictionary *)[extras valueForKey:k]]
                                  ]
            ];
        } else {
            [attributes addObject:[CLSAttribute of:key
                                             value:[extras valueForKey:k]
                                  ]
            ];
        }
    }
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

#pragma mark - CLSExtraProvider
@interface CLSExtraProvider()
@property(nonatomic, strong, readonly) NSMutableDictionary *dict;
@end

@implementation CLSExtraProvider : NSObject

- (instancetype)init {
    if (self = [super init]) {
        _dict = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void) setExtra: (NSString *)key value: (NSString *)value {
    [_dict setObject:[value copy] forKey:[key copy]];
}
- (void) setExtra: (NSString *)key dictValue: (NSDictionary<NSString *, NSString *> *)value {
    if (![value isKindOfClass:[NSDictionary<NSString *, NSString *> class]]) {
        return;
    }

    [_dict setObject:[value copy] forKey:[key copy]];
}
- (void) removeExtra: (NSString *)key {
    [_dict removeObjectForKey:key];
}
- (void) clearExtras {
    [_dict removeAllObjects];
}
- (NSDictionary<NSString *, NSString *> *) getExtras {
    return [_dict copy];
}
@end

