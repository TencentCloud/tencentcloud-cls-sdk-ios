#include "cls_signature.h"
#include <string.h>
#include <ctype.h>

#include "cls_rbtree.h"
#include <unistd.h>
#include "cls_map.h"
#include <CommonCrypto/CommonHMAC.h>

void _sha1(const void *data, size_t len,char *c_sha1)
{
    unsigned char digest[SHA_DIGEST_LENGTH];
    memset(digest, 0, SHA_DIGEST_LENGTH);
    SHA_CTX ctx;
    SHA1_Init(&ctx);
    SHA1_Update(&ctx, data, len);
    SHA1_Final(digest, &ctx);
    unsigned i = 0;
    for (; i < SHA_DIGEST_LENGTH; ++i)
    {
        sprintf(&c_sha1[i * 2], "%02x", (unsigned int)digest[i]);
    }
}

//void _hmac_sha1(const char *key, const void *data, size_t len, char *c_hmacsha1)
//{
//    unsigned char digest[EVP_MAX_MD_SIZE];
//    memset(digest, 0, EVP_MAX_MD_SIZE);
//    unsigned digest_len;
//    HMAC_CTX *ctx = HMAC_CTX_new();
//	HMAC_CTX_reset(ctx);
//    HMAC_Init_ex(ctx, key, strlen(key), EVP_sha1(), NULL);
//    HMAC_Update(ctx, (unsigned char *)data, len);
//    HMAC_Final(ctx, digest, &digest_len);
//    HMAC_CTX_free(ctx);
//    unsigned i = 0;
//    for (; i != digest_len; ++i)
//    {
//        sprintf(&c_hmacsha1[i * 2], "%02x", (unsigned int)digest[i]);
//    }
//}

void _hmac_sha1(const char *key, const void *data, size_t len, char *c_hmacsha1)
{
    unsigned char result[CC_SHA1_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA1, key, strlen(key), data, strlen(data), result);
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        sprintf(&c_hmacsha1[i * 2], "%02x", (unsigned int)result[i]);
    }
}


void urlencode(const char *s,unsigned char *c_url)
{
    static unsigned char hexchars[] = "0123456789ABCDEF";
    size_t pos = 0;
    const unsigned char *p = (const unsigned char *)s;
    for (; *p; ++p)
    {
        if (isalnum((unsigned char)*p) || (*p == '-') ||
            (*p == '_') || (*p == '.') || (*p == '~'))
        {
            c_url[pos++] = *p;
        }
        else
        {
            c_url[pos++] = '%';
            c_url[pos++] = hexchars[(*p) >> 4];
            c_url[pos++] = hexchars[(*p) & 15U];
        }
    }
    c_url[pos] = 0;
}

void signature(const char *secret_id,
               const char *secret_key,
               char *method,
               const char *path,
               const root_t params,
               const root_t headers,
               long expire,
               char *c_signature)
{

    const size_t SIGNLEN = 1024;
    char http_request_info[SIGNLEN];
    memset(http_request_info, 0, sizeof(http_request_info));

    char uri_parm_list[SIGNLEN];
    memset(uri_parm_list, 0, sizeof(uri_parm_list));

    char header_list[SIGNLEN];
    memset(header_list, 0, sizeof(header_list));

    char str_to_sign[SIGNLEN];
    memset(str_to_sign, 0, sizeof(str_to_sign));

    //把method转换为小写
    char lowermethod[32];
    strlowr(method, lowermethod);
    //字符串拼接
    strcat(http_request_info, lowermethod);
    strcat(http_request_info, "\n");
    strcat(http_request_info, path);
    strcat(http_request_info, "\n");

    //遍历params
    map_t *node;
    for (node = map_first(&params); node;)
    {
        strcat(uri_parm_list, node->key);
        strcat(http_request_info, node->key);
        strcat(http_request_info, "=");
        unsigned char c_url[strlen(node->val)*3+1];
        memset(c_url,0,strlen(node->val)*3+1);
        urlencode(node->val,c_url);
        strcat(http_request_info, c_url);
        node = map_next(&(node->node));
        if (node != NULL)
        {
            strcat(uri_parm_list, ";");
            strcat(http_request_info, "&");
        }
    }
    char sign_key[128];
    strcat(http_request_info, "\n");
    for (node = map_first(&headers); node; node = map_next(&(node->node)))
    {
        memset(sign_key,0,128);
        strlowr(node->key, sign_key);
        if ((strcmp(sign_key, "content-type") == 0) || (strcmp(sign_key, "content-md5") == 0) || (strcmp(sign_key, "host") == 0) || (sign_key[0] == 'x'))
        {
            strcat(header_list, sign_key);
            strcat(http_request_info, sign_key);
            strcat(http_request_info, "=");
            unsigned char c_url[strlen(node->val)*3+1];
            memset(c_url,0,strlen(node->val)*3+1);
            urlencode(node->val,c_url);
            strcat(http_request_info, c_url);
            strcat(header_list, ";");
            strcat(http_request_info, "&");
        }
    }

    if (strlen(header_list) != 0)
    {
        header_list[strlen(header_list) - 1] = 0;
        http_request_info[strlen(http_request_info) - 1] = '\n';
    }
    char signed_time[SIGNLEN];
    memset(signed_time, 0, sizeof(signed_time));
    int signed_time_len = snprintf(signed_time, SIGNLEN,
                                   "%lu;%lu", time(0) - 60, time(0) + expire);

    char signkey[EVP_MAX_MD_SIZE * 2 + 1];
    memset(signkey, 0, EVP_MAX_MD_SIZE * 2 + 1);
    _hmac_sha1(secret_key, signed_time, signed_time_len, signkey);
    strcat(str_to_sign, "sha1");
    strcat(str_to_sign, "\n");
    strcat(str_to_sign, signed_time);
    strcat(str_to_sign, "\n");
    char c_sha1[SHA_DIGEST_LENGTH * 2 + 1];
    memset(c_sha1,0,SHA_DIGEST_LENGTH * 2 + 1);
    _sha1(http_request_info, strlen(http_request_info),c_sha1);
    strcat(str_to_sign, c_sha1);
    strcat(str_to_sign, "\n");
    memset(c_signature, 0, SIGNLEN);

    char signature[EVP_MAX_MD_SIZE * 2 + 1];
    memset(signature, 0, EVP_MAX_MD_SIZE * 2 + 1);
    _hmac_sha1(signkey, str_to_sign, strlen(str_to_sign), signature);
    snprintf(c_signature, SIGNLEN,
             "q-sign-algorithm=sha1&q-ak=%s"
             "&q-sign-time=%s&q-key-time=%s"
             "&q-header-list=%s&q-url-param-list=%s&q-signature=%s",
             secret_id, signed_time, signed_time,
             header_list, uri_parm_list,
             signature);
}

void strlowr(char *src, char *dst)
{
    memset(dst, 0, strlen(src) + 1);
    int i = 0;
    for (; i < strlen(src); ++i)
    {
        dst[i] = tolower(src[i]);
    }
}
