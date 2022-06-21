//
//  sendcallback.h
//  TencentCloundLogSwiftDemo
//
//  Created by herrylv on 2022/5/26.
//

#ifndef sendcallback_h
#define sendcallback_h
#include <stdio.h>

void log_send_callback(const char * config_name, int result, size_t log_bytes, size_t compressed_bytes, const char * req_id, const char * message, const unsigned char * raw_buffer, void * userparams);
#endif /* sendcallback_h */
