//
//  CLSEvent.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

//
//  CLSEvent.m
//  Pods
//
//  Created by gordon on 2022/10/11.
//

#import "CLSEvent.h"

@interface CLSEvent ()
@property(nonatomic, strong) NSLock *lock;

@end
@implementation CLSEvent

+ (instancetype) eventWithName:(NSString *)name {
    CLSEvent *event = [[CLSEvent alloc] init];
    event.name = name;
    return event;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _attributes = [NSMutableArray array];
        _epochNanos = [[NSDate date] timeIntervalSince1970] * 1000000000;
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (instancetype) addAttribute:(CLSAttribute *) attribute, ... NS_REQUIRES_NIL_TERMINATION NS_SWIFT_UNAVAILABLE("use addAttributes instead.") {
    if (nil == attribute) {
        return self;
    }
    
    NSMutableArray<CLSAttribute*> *attrs = (NSMutableArray<CLSAttribute*>  *) _attributes;
    [_lock lock];
    [attrs addObject:attribute];
    _totalAttributeCount += 1;
    
    va_list args;
    CLSAttribute *arg;
    va_start(args, attribute);
    while ((arg = va_arg(args, CLSAttribute*))) {
        [attrs addObject:arg];
        _totalAttributeCount += 1;
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
    _totalAttributeCount += attributes.count;
    [_lock unlock];
    return self;
}
@end

