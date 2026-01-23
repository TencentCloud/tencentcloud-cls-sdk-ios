//
//  CLSSPanBuilder.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import "CLSSpanBuilder.h"
#import "CLSIdGenerator.h"
#import "CLSSpanProviderProtocol.h"
#import "CLSAttribute.h"
#import "CLSResource.h"
#import "CLSRecordableSpan.h"
#import "CLSPrivocyUtils.h"
#import "TencentCloudLogProducer/ClsLogs.pbobjc.h"
#import "TencentCloudLogProducer/ClsLogStorage.h"

@interface CLSSpanBuilder ()
@property(nonatomic, strong) NSString *name;
@property(nonatomic, strong) NSString *url;
@property(nonatomic, strong) NSString *pageName;
@property(nonatomic, strong) NSString *customTraceId;
@property(nonatomic, strong) id<CLSSpanProviderProtocol> spanProvider;
@property(atomic, assign, readonly) BOOL active;
@property(nonatomic, strong) NSMutableArray<CLSAttribute*> *attributes;
@property(nonatomic, strong, readonly) CLSResource *resource;
@property(nonatomic, assign, readonly) long start;
@property(nonatomic, strong, readonly) NSString *service;
@property(atomic, assign, readonly) BOOL global;
@end

@implementation CLSSpanBuilder

+ (CLSSpanBuilder *) builder {
    return [[CLSSpanBuilder alloc] init];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _attributes = [NSMutableArray<CLSAttribute*> array];
        _start = [[NSDate date] timeIntervalSince1970] * 1000000000;
        _global = YES;
    }
    return self;
}
- (CLSSpanBuilder *) initWithName: (NSString *)name provider: (id<CLSSpanProviderProtocol>) provider{
    self = [self init];
    if (self) {
        _name = name;
        _spanProvider = provider;
    }
    return self;
}

- (CLSSpanBuilder *) setActive: (BOOL) active {
    _active = active;
    return self;
}

- (CLSSpanBuilder *) setURL: (NSString *)url {
    _url = url;
    return self;
}

- (CLSSpanBuilder *) setpageName: (NSString *)pageName {
    _pageName = pageName;
    return self;
}

- (CLSSpanBuilder *) setTraceId: (NSString *)traceId {
    _customTraceId = traceId;
    return self;
}


- (CLSSpanBuilder *) addAttribute: (CLSAttribute *) attribute, ... NS_REQUIRES_NIL_TERMINATION {
    [_attributes addObject:attribute];
    
    va_list args;
    CLSAttribute *arg;
    va_start(args, attribute);
    while ((arg = va_arg(args, CLSAttribute*))) {
        [_attributes addObject:arg];
    }
    va_end(args);
    
    return self;
}

- (CLSSpanBuilder *) addAttributes: (NSArray<CLSAttribute *> *) attributes {
    [_attributes addObjectsFromArray:attributes];
    return self;
}

- (CLSSpanBuilder *) setStart: (long) start {
    _start = start;
    return self;
}
- (CLSSpanBuilder *) addResource: (CLSResource *) resource {
    _resource = resource;
    return self;
}
- (CLSSpanBuilder *) setService: (NSString *)service {
    _service = service;
    return self;
}
- (CLSSpanBuilder *) setGlobal: (BOOL) global {
    _global = global;
    return self;
}
- (CLSSpan *) build {
    CLSRecordableSpan *span = [[CLSRecordableSpan alloc] init];
    span.name = _name;
    span.service = _service;
    span.traceID = _customTraceId ?: CLSIdGenerator.generateTraceId;
    
//    if (nil != _spanProvider) {
//        [_attributes addObjectsFromArray:[_spanProvider provideAttribute]];
//    }
    NSMutableDictionary<NSString *, NSString *> *dict = (NSMutableDictionary<NSString *, NSString *> *) span.attribute;
    for (CLSAttribute *attr in _attributes) {
        if (attr.key && attr.value) {
            [dict setObject:attr.value forKey:attr.key];
        }
    }
    
    CLSResource *r = [CLSResource resource];
    if (nil != _spanProvider) {
        [r merge:[_spanProvider provideResource]];
    }
    if (nil != _resource) {
        [r merge:_resource];
    }
    span.resource = r;
    [span setGlobal: _global];
    
    if (_start != 0L) {
        span.start = _start;
    } else {
        span.start = [[NSDate date] timeIntervalSince1970] * 1000000000;
    }
    
    return span;
}

- (NSDictionary *)report:(NSString*)topicId reportData:(NSDictionary *)reportData{
    if (!reportData) {
        return @{};
    }
    
    NSDictionary *dict = [reportData copy];
    
    NSString *method = [dict objectForKey:@"method"]?:@"";
    [CLSPrivocyUtils setEnablePrivocy:YES];
    [self addAttribute:
         [CLSAttribute of:@"net.type" value:method],
         [CLSAttribute of:@"page.name" value:self.pageName],
         [CLSAttribute of:@"net.origin" dictValue:dict],
         nil
    ];
    [self setGlobal:NO];
    CLSSpan *span = [self build];
    [span end];
    NSDictionary *d = [span toDict];
    Log *logItem = [Log message];
    for (NSString *key in d) {
        NSString *value = d[key];
        // 兼容空值，避免写入nil导致失败
        if (!value) value = @"";
        
        // 创建单条日志内容（对应原有 PutClsContent 逻辑）
        Log_Content *content = [Log_Content message];
        content.key = key;       // 原有字典key
        content.value = value;   // 原有字典value
        [logItem.contentsArray addObject:content]; // 添加到日志内容列表
    }
    [[ClsLogStorage sharedInstance] writeLog:logItem
                                     topicId:topicId // 可传入配置的topicId，或复用LogSender的配置
                                   completion:^(BOOL success, NSError *error) {
        if (success) {
            NSLog(@"日志写入成功，包含 %ld 个字段", d.count);
        } else {
            NSLog(@"日志写入失败，error：%@", error);
        }
    }];
    return d;
}

@end

