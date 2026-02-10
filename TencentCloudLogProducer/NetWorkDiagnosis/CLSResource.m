//
//  CLSResource.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import "CLSResource.h"
#import "CLSKeyValue.h"

@interface CLSResource()
@property(nonatomic, strong) NSLock *lock;
@end

@implementation CLSResource

+ (instancetype) resource {
    return [[CLSResource alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (nil != self) {
        _attributes = [NSMutableArray array];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (void) add: (NSString *)key value: (NSString *)value {
    [_lock lock];
    NSMutableArray<CLSAttribute*> *array = (NSMutableArray<CLSAttribute*>*) _attributes;
    [array addObject:[CLSAttribute of:key value:value]];
    
    [_lock unlock];
}

- (void) add: (NSArray<CLSAttribute *> *)attributes {
    [_lock lock];
    NSMutableArray<CLSAttribute*> *array = (NSMutableArray<CLSAttribute*>*) _attributes;
    [array addObjectsFromArray:attributes];
    [_lock unlock];
}

- (void) merge: (CLSResource *)resource {
    if (!resource || !resource.attributes) {
        return;
    }
    [_lock lock];
    NSMutableArray<CLSAttribute*> *array = (NSMutableArray<CLSAttribute*>*) _attributes;
    [array addObjectsFromArray:resource.attributes];
    [_lock unlock];
}

- (NSDictionary *) toDictionary {
    NSMutableArray<NSDictionary *> *array = [NSMutableArray array];
    for (CLSAttribute *attribute in _attributes) {
        [array addObject:@{
            @"key": attribute.key,
            @"value": @{
                @"stringValue": attribute.value
            }
        }];
    }
    
    return @{
        @"attributes": array
    };
}

+ (CLSResource*) of: (NSString *)key value: (NSString *)value {
    CLSResource *resource = [[CLSResource alloc] init];
    [resource add:key value:value];
    return resource;
}

+ (CLSResource*) of: (CLSKeyValue*)keyValue, ...NS_REQUIRES_NIL_TERMINATION {
    CLSResource *resource = [[CLSResource alloc] init];
    [resource add:keyValue.key value:keyValue.value];
    
    va_list args;
    CLSKeyValue *arg;
    va_start(args, keyValue);
    while ((arg = va_arg(args, CLSKeyValue*))) {
        [resource add:arg.key value:arg.value];
    }
    va_end(args);
    
    return resource;
}
+ (CLSResource *) ofAttributes: (NSArray<CLSAttribute *> *)attributes {
    CLSResource *resource = [CLSResource resource];
    NSMutableArray<CLSAttribute *> *attrs = (NSMutableArray<CLSAttribute *> *) resource.attributes;
    [attrs addObjectsFromArray:attributes];
    return resource;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    CLSResource *r = [CLSResource resource];
    r.attributes = [NSMutableArray arrayWithArray:self.attributes];
    return r;
}

- (id)mutableCopyWithZone:(nullable NSZone *)zone {
    CLSResource *r = [CLSResource resource];
    r.attributes = [NSMutableArray arrayWithArray:self.attributes];
    return r;
}

@end

