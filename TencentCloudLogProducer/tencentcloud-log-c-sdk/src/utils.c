//
//  utils.c
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/7/1.
//

#include "utils.h"


void arr_to_string(const char** in, const int inlen,char *out) {
    if(in == NULL || out == NULL){
        return;
    }
//    char *p = out;
    int i = 0;
    for(; i < inlen; ++i){
        strncat(out,in[i],strlen(in[i]));
        out += strlen(in[i]);
        if(i != (inlen-1)){
            strncat(out,",",1);
            out++;
        }
        
    }
    *out = '\0';
//    *p++ = '\0';
    
}

char* get_local_ip(const char *eth_inf)
{
    int sd;
    struct sockaddr_in sin;
    struct ifreq ifr;
 
    sd = socket(AF_INET, SOCK_DGRAM, 0);
    if (-1 == sd)
    {
        return NULL;
    }
 
    strncpy(ifr.ifr_name, eth_inf, IFNAMSIZ);
    ifr.ifr_name[IFNAMSIZ - 1] = 0;
 
    // if error: No such device
    if (ioctl(sd, SIOCGIFADDR, &ifr) < 0)
    {
        close(sd);
        return NULL;
    }

    close(sd);
    return inet_ntoa(((struct sockaddr_in*)&ifr.ifr_addr)->sin_addr);
}
