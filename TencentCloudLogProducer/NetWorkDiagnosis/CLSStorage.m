//
//  CLSStorage.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import "CLSStorage.h"

@interface CLSStorage ()
+ (NSString *) getFile;
@end

@implementation CLSStorage
+ (NSString *) getFile {
    NSString *libraryPath = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSLog(@"CLSStorage. libraryPath: %@", libraryPath);

    NSString *clsRootDir = [libraryPath stringByAppendingPathComponent:@"cls-ios"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:clsRootDir]) {
        BOOL res = [fileManager createDirectoryAtPath:clsRootDir withIntermediateDirectories:YES attributes:nil error:nil];
        if(!res) {
            return @"";
        }
    }

    return [clsRootDir stringByAppendingPathComponent:@"files"];
}

+ (void) setUtdid: (NSString *)utdid {
    NSString *files = [self getFile];
    if (!files) {
        return;
    }
    
    [utdid writeToFile:files atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

+ (NSString *) getUtdid {
    NSString *files = [self getFile];
    if(!files) {
        return @"";
    }
    
    NSString *content = [NSString stringWithContentsOfFile:files encoding:NSUTF8StringEncoding error:nil];
    if(!content) {
        return @"";
    }
    
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    NSString *utdid = @"";
    for (NSString *line in lines) {
        utdid = line;
        break;
    }
    
    return [utdid copy];
}
@end
