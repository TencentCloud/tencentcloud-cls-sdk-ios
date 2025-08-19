#ifndef CLS_LOG_H
#define CLS_LOG_H

#import <Foundation/Foundation.h>

@interface ClsLog : NSObject
{
    @package uint64_t logTime;
    @package NSMutableDictionary *content;
}

- (void)PutClsContent:(NSString *) key value:(NSString *)value;

- (NSMutableDictionary *) getClsContent;

- (void)SetClsTime:(unsigned int) logTime;

- (unsigned int) getClsTime;

@end


#endif /* CLS_LOG_H */
