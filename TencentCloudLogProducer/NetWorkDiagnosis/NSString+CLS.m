//
//  NSString+CLS.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//
#import "NSString+CLS.h"

@implementation NSString (CLS)
- (NSString *) base64Encode {
    return [[self dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
}

- (NSString *) base64Decode {
    return [[NSString alloc] initWithData:[[NSData alloc] initWithBase64EncodedString:self
                                                                              options:NSDataBase64DecodingIgnoreUnknownCharacters
                                          ]
                                 encoding:NSUTF8StringEncoding
    ];
}

- (NSDictionary *) toDictionary {
    NSData *data = [self dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data
                                    options:kNilOptions
                                      error:&error
    ];
    if (error) {
        NSLog(@"NSString to NSDictionary error. %@", error);
        return [NSDictionary dictionary];
    }
    
    return dict;
}

+ (NSString *) stringWithDictionary: (NSDictionary *) dictionary {
    if (![NSJSONSerialization isValidJSONObject:dictionary]) {
        return [NSString string];
    }
    
    NSJSONWritingOptions options = kNilOptions;
    if (@available(iOS 11.0, macOS 10.13, watchOS 4.0, tvOS 11.0, *)) {
        options = NSJSONWritingSortedKeys;
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary
                                                   options:options
                                                     error:&error
    ];
    
    if (nil != error) {
        return [NSString string];
    }
    
    return [[NSString alloc] initWithData:data
                                 encoding:NSUTF8StringEncoding
    ];
}
@end

