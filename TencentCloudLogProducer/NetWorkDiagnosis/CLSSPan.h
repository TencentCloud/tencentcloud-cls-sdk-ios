//
//  CLSSPan.m
//  TencentCloudLogProducer
//
//  Created by hao lv on 2025/10/10.
//

#import <Foundation/Foundation.h>
#import "CLSResource.h"
#import "CLSEvent.h"
#import "CLSLink.h"

NS_ASSUME_NONNULL_BEGIN
typedef NSString *CLSKind NS_STRING_ENUM;
FOUNDATION_EXPORT CLSKind const CLSINTERNAL;
FOUNDATION_EXPORT CLSKind const CLSSERVER;
FOUNDATION_EXPORT CLSKind const CLSCLIENT;
FOUNDATION_EXPORT CLSKind const CLSPRODUCER;
FOUNDATION_EXPORT CLSKind const CLSCONSUMER;

typedef NS_ENUM(NSInteger, CLSStatusCode){
    UNSET = 0,
    OK = 1,
    ERROR = 2
};

@interface CLSSpan : NSObject

@property(nonatomic, strong) NSString* name;
@property(nonatomic, strong) NSString* traceID;
@property(nonatomic, assign) long start;
@property(nonatomic, assign, getter=getEndTime) long end;
@property(nonatomic, assign) long duration;
@property(nonatomic, strong) NSDictionary<NSString*, NSString*>* attribute;
@property(nonatomic, strong, readonly) NSArray<CLSEvent*> *evetns;
@property(nonatomic, strong, readonly) NSArray<CLSLink*> *links;
//@property(nonatomic, strong) NSString *host;
@property(nonatomic, strong) CLSResource *resource;
@property(nonatomic, strong) NSString *service;
@property(atomic, assign, readonly) BOOL isEnd;
@property(atomic, assign, readonly) BOOL isGlobal;

/// Add CLSAttributes to CLSSpan
/// @param attribute CLSAttribute
- (CLSSpan *) addAttribute:(CLSAttribute *)attribute, ... NS_REQUIRES_NIL_TERMINATION NS_SWIFT_UNAVAILABLE("use addAttributes instead.");

/// Add CLSAttributes to CLSSpan.
/// @param attributes CLSAttribute array.
- (CLSSpan *) addAttributes:(NSArray<CLSAttribute*> *)attributes NS_SWIFT_NAME(addAttributes(_:));

/// Add CLSResource to current CLSSpan.
/// @param resource CLSResource
- (CLSSpan *) addResource: (CLSResource *) resource;

- (CLSSpan *) addEvent:(NSString *)name;
- (CLSSpan *) addEvent:(NSString *)name attribute: (CLSAttribute *)attribute, ... NS_REQUIRES_NIL_TERMINATION;
- (CLSSpan *) addEvent:(NSString *)name attributes:(NSArray<CLSAttribute *> *)attributes;

- (CLSSpan *) addLink: (CLSLink *)link, ... NS_REQUIRES_NIL_TERMINATION NS_SWIFT_UNAVAILABLE("use addLinks instead.");
- (CLSSpan *) addLinks: (NSArray<CLSLink *> *)links NS_SWIFT_NAME(addLinks(_:));

- (CLSSpan *) recordException:(NSException *)exception NS_SWIFT_NAME(recordException(_:));
- (CLSSpan *) recordException:(NSException *)exception attribute: (CLSAttribute *)attribute, ... NS_REQUIRES_NIL_TERMINATION NS_SWIFT_UNAVAILABLE("use recordException(_:attributes) instead.");
- (CLSSpan *) recordException:(NSException *)exception attributes:(NSArray<CLSAttribute *> *)attribute NS_SWIFT_NAME(recordException(_:attributes:));
/// End current CLSSpan
- (BOOL) end;

/// Convert current CLSSpan to NSDictionary
- (NSDictionary<NSString*, NSString*> *) toDict;

- (CLSSpan *) setGlobal: (BOOL) global;

- (CLSSpan *) setScope: (void (^)(void)) scope;

@end

NS_ASSUME_NONNULL_END
