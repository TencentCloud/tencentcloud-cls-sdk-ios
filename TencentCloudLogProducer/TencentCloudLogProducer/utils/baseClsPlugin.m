//
//  baseClsPlugin.m
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import "baseClsPlugin.h"

@implementation baseClsPlugin
- (NSString *)name {
    return @"baseClsPlugin";
}
- (BOOL) initWithCLSConfig: (ClsConfig *) config {
    NSLog(@"plugin: %@ initWithCLSConfig", self.name);
    return YES;
}
@end
