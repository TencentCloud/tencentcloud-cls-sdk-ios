//
//  basePlugin.m
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/6/7.
//

#import "basePlugin.h"

@implementation basePlugin
- (NSString *)name {
    return @"basePlugin";
}
- (BOOL) initWithCLSConfig: (CLSConfig *) config {
    NSLog(@"plugin: %@ initWithCLSConfig", self.name);
    return YES;
}
@end
