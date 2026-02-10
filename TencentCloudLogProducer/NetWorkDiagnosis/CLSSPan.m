//
//  CLSSPan.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import "CLSSpan.h"

NSString* const CLSINTERNAL = @"INTERNAL";
NSString* const CLSSERVER = @"SERVER";
NSString* const CLSCLIENT = @"CLIENT";
NSString* const CLSPRODUCER = @"PRODUCER";
NSString* const CLSCONSUMER = @"CONSUMER";

typedef void (^_internal_Scope)(void);

@interface CLSSpan ()
@property(nonatomic, strong, readonly) _internal_Scope scope;
@property(nonatomic, strong) NSLock *lock;
- (void) addEventInternal:(CLSEvent *)event;
@end

@implementation CLSSpan

- (instancetype)init
{
    self = [super init];
    if (self) {
        _attribute = [NSMutableDictionary<NSString*, NSString*> dictionary];
        _evetns = [NSMutableArray<CLSEvent*> array];
        _links = [NSMutableArray<CLSLink*> array];
        _resource = [[CLSResource alloc] init];
        _isGlobal = YES;
        _lock = [[NSLock alloc] init];
    }

    return self;
}

- (CLSSpan *) addAttribute:(CLSAttribute *)attribute, ... NS_REQUIRES_NIL_TERMINATION {
    [_lock lock];
    NSMutableDictionary<NSString*, NSString*> *dict = (NSMutableDictionary<NSString*, NSString*> *) _attribute;
    [dict setObject:attribute.value forKey:attribute.key];
    va_list args;
    CLSAttribute *arg;
    va_start(args, attribute);
    while ((arg = va_arg(args, CLSAttribute*))) {
        [dict setObject:arg.value forKey:arg.key];
    }
    va_end(args);
    [_lock unlock];
    return self;
}

- (CLSSpan *) addAttributes:(NSArray<CLSAttribute*> *)attributes {
    [_lock lock];
    NSMutableDictionary<NSString*, NSString*> *dict = (NSMutableDictionary<NSString*, NSString*> *) _attribute;
    
    for (CLSAttribute *attr in attributes) {
        [dict setObject:attr.value forKey:attr.key];
    }
    [_lock unlock];
    return self;
}
- (CLSSpan *) addResource: (CLSResource *) resource {
    if (resource) {
        [_lock lock];
        [_resource merge:resource];
        [_lock unlock];
    }
    
    return self;
}
- (CLSSpan *) addEvent:(NSString *)name {
    [self addEventInternal:[CLSEvent eventWithName:name]];
    return self;
}
- (CLSSpan *) addEvent:(NSString *)name attribute: (CLSAttribute *)attribute, ... NS_REQUIRES_NIL_TERMINATION {
    CLSEvent *event = [CLSEvent eventWithName:name];
    [event addAttribute:attribute, nil];

    va_list args;
    CLSAttribute *arg;
    va_start(args, attribute);
    while ((arg = va_arg(args, CLSAttribute*))) {
        [event addAttribute:arg, nil];
    }
    va_end(args);

    [self addEventInternal:event];
    return self;
}
- (CLSSpan *) addEvent:(NSString *)name attributes:(NSArray<CLSAttribute *> *)attributes {
    [self addEventInternal:
         [[CLSEvent eventWithName:name] addAttributes:attributes]
    ];
    return self;
}

- (CLSSpan *) addLink: (CLSLink *)link, ... NS_REQUIRES_NIL_TERMINATION {
    NSMutableArray<CLSLink*> *links = (NSMutableArray<CLSLink*> *)_links;
    [_lock lock];
    [links addObject:link];
    [_lock unlock];
    
    va_list args;
    CLSLink *arg;
    va_start(args, link);
    while ((arg = va_arg(args, CLSLink*))) {
        [_lock lock];
        [links addObject:arg];
        [_lock unlock];
    }
    va_end(args);
    
    return self;
}
- (CLSSpan *) addLinks: (NSArray<CLSLink *> *)links {
    if (nil == links) {
        return self;
    }
    [_lock lock];
    [((NSMutableArray<CLSLink*> *)_links) addObjectsFromArray:links];
    [_lock unlock];
    return self;
}

- (CLSSpan *) recordException:(NSException *)exception {
    return [self recordException:exception attributes:[NSArray array]];
}
- (CLSSpan *) recordException:(NSException *)exception attribute: (CLSAttribute *)attribute, ... NS_REQUIRES_NIL_TERMINATION {
    NSMutableArray<CLSAttribute *> *attr = [NSMutableArray array];
    if (nil != attribute) {
        [attr addObject:attribute];
    }

    va_list args;
    CLSAttribute *arg;
    va_start(args, attribute);
    while ((arg = va_arg(args, CLSAttribute*))) {
        [attr addObject:arg];
    }
    va_end(args);

    return [self recordException:exception attributes:attr];
}
- (CLSSpan *) recordException:(NSException *)exception attributes:(NSArray<CLSAttribute *> *)attribute {
    CLSEvent *event = [[CLSEvent eventWithName:@"exception"] addAttribute:
                           [CLSAttribute of:@"exception.type" value:exception.name],
                           [CLSAttribute of:@"exception.message" value:exception.reason],
                           [CLSAttribute of:@"exception.stacktrace" value:(exception.callStackSymbols ? [[exception.callStackSymbols valueForKey:@"description"] componentsJoinedByString:@"\n"] : @"")],
                           nil
    ];

    [event addAttributes:attribute];

    [self addEventInternal:event];
    return self;
}

- (void) addEventInternal:(CLSEvent *)event {
    [_lock lock];
    [((NSMutableArray<CLSEvent*> *) _evetns) addObject:event];
    [_lock unlock];
}

- (BOOL) end {
    [_lock lock];
    if (_isEnd) {
        return NO;
    }
    _isEnd = YES;
    _end = [[NSDate date] timeIntervalSince1970] * 1000000000;
    
    _duration = _end - _start;
    if (nil != _scope) {
        _scope();
    }
    [_lock unlock];
    return YES;
}

- (NSDictionary<NSString*, NSString*> *) toDict {
    [_lock lock];
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    [dict setObject:_name forKey:@"name"];
    [dict setObject:_traceID forKey:@"traceID"];
    [dict setObject:[NSString stringWithFormat:@"%ld", _start] forKey:@"start"];
    [dict setObject:[NSString stringWithFormat:@"%ld", _duration] forKey:@"duration"];
    [dict setObject:[NSString stringWithFormat:@"%ld", _end] forKey:@"end"];
    // service name default: iOS
    [dict setObject:_service.length > 0 ? _service : @"iOS" forKey:@"service"];
    
    NSMutableDictionary<NSString*, NSString*> *attributeDict = [NSMutableDictionary<NSString*, NSString*> dictionary];
    for (NSString* key in [_attribute allKeys]) {
        [attributeDict setObject:[_attribute valueForKey:key] forKey:key];
    }
    
    [dict setObject:[self stringWithDictionary:attributeDict] forKey:@"attribute"];
    
    if (_resource.attributes) {
        NSMutableDictionary<NSString*, NSString*> *resourceDict = [NSMutableDictionary<NSString*, NSString*> dictionary];
        for (CLSAttribute *attr in _resource.attributes) {
            [resourceDict setObject:attr.value forKey:attr.key];
        }

        [dict setObject:[self stringWithDictionary: resourceDict] forKey:@"resource"];
    }
    
    if (_evetns && [_evetns count] > 0) {
        NSMutableArray *logs = [NSMutableArray array];
        for (CLSEvent *event in _evetns) {
            NSMutableDictionary *object = [NSMutableDictionary dictionary];
            [object setObject:(event.name.length > 0 ? event.name : @"") forKey:@"name"];
            [object setObject:[[NSNumber numberWithLong:event.epochNanos] stringValue] forKey:@"epochNanos"];
            [object setObject:[[NSNumber numberWithInt:event.totalAttributeCount] stringValue] forKey:@"totalAttributeCount"];
            
            NSArray<CLSAttribute *> *attributes = event.attributes;
            NSMutableDictionary<NSString*, NSString*> *attrObject = [NSMutableDictionary dictionary];
            for (CLSAttribute *attr in attributes) {
                [attrObject setObject:attr.value forKey:attr.key];
            }
            [object setObject:attrObject forKey:@"attributes"];
            
            [logs addObject:object];
        }

        [dict setObject:logs forKey:@"logs"];
    }
    
    if (_links && _links.count > 0) {
        NSMutableArray *links = [NSMutableArray array];
        for (CLSLink *link in _links) {
            NSMutableDictionary *object = [NSMutableDictionary dictionary];
            [object setObject:(link.traceId.length > 0 ? link.traceId : @"") forKey:@"traceID"];
            [object setObject:(link.spanId.length > 0 ? link.spanId : @"") forKey:@"spanID"];
            
            NSArray<CLSAttribute *> *attributes = link.attributes;
            NSMutableDictionary<NSString*, NSString*> *attrObject = [NSMutableDictionary dictionary];
            for (CLSAttribute *attr in attributes) {
                [attrObject setObject:attr.value forKey:attr.key];
            }
            [object setObject:attrObject forKey:@"attributes"];
            
            [links addObject:object];
        }
        
        [dict setObject:links forKey:@"links"];
    }
    [_lock unlock];
    return dict;
}

- (CLSSpan *) setGlobal: (BOOL) global {
    [_lock lock];
    _isGlobal = global;
    [_lock unlock];
    return self;
}

- (CLSSpan *) setScope: (void (^)(void)) scope {
    [_lock lock];
    _scope = scope;
    [_lock unlock];
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    CLSSpan *span = [[CLSSpan alloc] init];

    [_lock lock];
    span.name = _name;
    span.traceID = _traceID;
    span.start = _start;
    span.end = _end;
    span.duration = _duration;
    span.attribute = _attribute;
    span.resource = [_resource copy];
    span.service = _service;
    span->_isEnd = _isEnd;
    [_lock unlock];
    return span;
}

- (NSString *) stringWithDictionary: (NSDictionary *) dictionary {
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

