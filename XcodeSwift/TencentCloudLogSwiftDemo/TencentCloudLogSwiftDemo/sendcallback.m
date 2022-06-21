//
//  sendcallback.c
//  TencentCloundLogSwiftDemo
//
//  Created by herrylv on 2022/5/26.
//

#include "sendcallback.h"
#include "log_error.h"
#import "TencentCloudLogProducer.h"

void log_send_callback(const char * config_name, int result, size_t log_bytes, size_t compressed_bytes, const char * req_id, const char * message, const unsigned char * raw_buffer, void * userparams) {
    if (result == LOG_PRODUCER_OK) {
        NSString *success = [NSString stringWithFormat:@"send success, topic : %s, result : %d, log bytes : %d, compressed bytes : %d, request id : %s", config_name, (result), (int)log_bytes, (int)compressed_bytes, req_id];
        CLSLogV("%@", success);
        
//        [selfClzz UpdateReult:success];
    } else {
        NSString *fail = [NSString stringWithFormat:@"send fail   , topic : %s, result : %d, log bytes : %d, compressed bytes : %d, request id : %s, error message : %s", config_name, (result), (int)log_bytes, (int)compressed_bytes, req_id, message];
        CLSLogV("%@", fail);
        
//        [selfClzz UpdateReult:fail];
    }
}
