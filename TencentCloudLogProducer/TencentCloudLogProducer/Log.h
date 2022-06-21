

#ifndef Log_h
#define Log_h


#endif /* Log_h */

@interface Log : NSObject
{
    @package uint64_t logTime;
    @package NSMutableDictionary *content;
}

- (void)PutContent:(NSString *) key value:(NSString *)value;

- (NSMutableDictionary *) getContent;

- (void)SetTime:(unsigned int) logTime;

- (unsigned int) getTime;

@end
