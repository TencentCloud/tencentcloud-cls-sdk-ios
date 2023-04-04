//
//  utils.h
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/7/1.
//

#ifndef utils_h
#define utils_h

#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <netdb.h>
#include <net/if.h>
#include <arpa/inet.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/time.h> 

void arr_to_string(const char** in, const int inlen,char *out);
char* get_local_ip(const char *eth_inf);
#endif /* utils_h */
