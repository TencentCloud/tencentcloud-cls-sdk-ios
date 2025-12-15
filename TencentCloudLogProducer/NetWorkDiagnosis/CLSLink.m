//
//  CLSLink.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import "CLSLink.h"
#import "CLSAttribute.h"

@interface CLSLink ()
@property(nonatomic, strong) NSLock *lock;
@end

@implementation CLSLink
- (instancetype)init
{
    self = [super init];
    if (self) {
        _attributes = [NSMutableArray<CLSAttribute *> array];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

+ (instancetype) linkWithTraceId: (NSString *)traceId spanId:(NSString *)spanId {
    CLSLink *link = [[CLSLink alloc] init];
    link.traceId = traceId;
    link.spanId = spanId;
    return  link;
}
- (instancetype) addAttribute:(CLSAttribute *) attribute, ... NS_REQUIRES_NIL_TERMINATION NS_SWIFT_UNAVAILABLE("use addAttributes instead.") {
    if (nil == attribute) {
        return self;
    }
    
    NSMutableArray<CLSAttribute*> *attrs = (NSMutableArray<CLSAttribute*>  *) _attributes;
    [_lock lock];
    [attrs addObject:attribute];
    
    va_list args;
    CLSAttribute *arg;
    va_start(args, attribute);
    while ((arg = va_arg(args, CLSAttribute*))) {
        [attrs addObject:arg];
    }
    va_end(args);
    [_lock unlock];
    return self;
}

- (instancetype) addAttributes:(NSArray<CLSAttribute *> *)attributes {
    if (nil == attributes || attributes.count == 0) {
        return self;
    }
    
    [_lock lock];
    [((NSMutableArray<CLSAttribute*>  *) _attributes) addObjectsFromArray:attributes];
    [_lock unlock];
    return self;
}

@end

