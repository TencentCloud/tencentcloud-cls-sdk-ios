//
//  utils.c
//  TencentCloudLogProducer
//
//  Created by herrylv on 2022/7/1.
//

#include "cls_utils.h"


void cls_arr_to_string(const char** in, const int inlen,char *out) {
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

char* cls_get_local_ip(const char *eth_inf)
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

// 1 retry 0 not retry
int isNeedRetryWithErrorCode(int errCode){
    if((errCode >= 500 && errCode < 600) || errCode == 429 || errCode == 408 || errCode == 403 || errCode <= 0){
        return 1;
    }
    return 0;
}

void generate_uuid_v4(char *uuid_str) {
    unsigned char bytes[16];
    
    // 使用rand()生成随机数（仅为演示，不推荐用于生产）
    srand((unsigned int)time(NULL));
    for (int i = 0; i < 16; i++) {
        bytes[i] = rand() % 256;
    }
    
    // 设置版本号和变体
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // 版本4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // 标准变体
    
    // 格式化为字符串
    snprintf(uuid_str, 37, "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]);
}
