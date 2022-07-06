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
