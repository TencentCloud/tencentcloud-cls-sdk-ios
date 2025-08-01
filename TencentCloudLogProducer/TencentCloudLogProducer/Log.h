

#ifndef Log_h
#define Log_h


#endif /* Log_h */

@interface Log : NSObject
{
    @package int64_t logTime;
    @package NSMutableDictionary *content;
}

- (void)PutContent:(NSString *) key value:(NSString *)value;

- (NSMutableDictionary *) getContent;

- (void)SetTime:(int64_t) logTime;

- (int64_t) getTime;

@end
