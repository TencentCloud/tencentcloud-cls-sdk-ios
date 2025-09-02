#ifndef CLS_LOG_H
#define CLS_LOG_H

#import <Foundation/Foundation.h>

@interface ClsLog : NSObject
{
    @package int64_t logTime;
    @package NSMutableDictionary *content;
}

- (void)PutClsContent:(NSString *) key value:(NSString *)value;

- (NSMutableDictionary *) getClsContent;

- (void)SetClsTime:(int64_t) logTime;

- (int64_t) getClsTime;

@end


#endif /* CLS_LOG_H */
