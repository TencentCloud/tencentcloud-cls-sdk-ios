//
//  network_ios.h
//  network_ios
//
//  Created by zhanxiangli on 2025/12/9.
//

#import <Foundation/Foundation.h>

//! Project version number for network_ios.
FOUNDATION_EXPORT double network_iosVersionNumber;

//! Project version string for network_ios.
FOUNDATION_EXPORT const unsigned char network_iosVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <network_ios/PublicHeader.h>
// 确保在 Xcode 的 Build Phases -> Headers 中将 cls_ping_detector.h 标记为 Public
#import <network_ios/cls_ping_detector.h>
#import <network_ios/cls_dns_detector.h>
