#include "cls_map.h"
#include <openssl/hmac.h>
//#include <hmac.h>
#include <openssl/sha.h>
//#include <sha.h>
#include <stdio.h>
#include <string.h>

void _sha1(const void *data, size_t len,char *c_sha1);

void _hmac_sha1(const char *key, const void *data, size_t len,
                char *c_hmacsha1);

void urlencode(const char *s, unsigned char *c_url);

void signature(const char *secret_id, const char *secret_key, char *method,
               const char *path, const root_t params, const root_t headers,
               long expire, char *c_signature);

void strlowr(char *src, char *dst);
