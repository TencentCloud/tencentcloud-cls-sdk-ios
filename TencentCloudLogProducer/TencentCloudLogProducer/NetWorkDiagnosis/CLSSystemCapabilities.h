//
//  CLSSystemCapabilities.h
//  Pods
//
//  Created by herrylv on 2022/6/8.
//

#ifndef CLSSystemCapabilities_h
#define CLSSystemCapabilities_h

#ifdef __APPLE__
#include <TargetConditionals.h>
#define CLS_HOST_APPLE 1
#endif

#define CLS_HOST_IOS (CLS_HOST_APPLE && TARGET_OS_IOS)
#define CLS_HOST_TV (CLS_HOST_APPLE && TARGET_OS_TV)
#define CLS_HOST_WATCH (CLS_HOST_APPLE && TARGET_OS_WATCH)
#define CLS_HOST_MAC (CLS_HOST_APPLE && TARGET_OS_MAC && !(TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_WATCH)) || (CLS_HOST_APPLE && TARGET_OS_MACCATALYST)

#if CLS_HOST_IOS || CLS_HOST_TV || CLS_HOST_WATCH
#define CLS_HAS_UIKIT 1
#else
#define CLS_HAS_UIKIT 0
#endif

#if CLS_HOST_IOS && !TARGET_OS_MACCATALYST
#define CLS_HAS_CORE_TELEPHONY 1
#else
#define CLS_HAS_CORE_TELEPHONY 0
#endif
#endif /* CLSSystemCapabilities_h */
