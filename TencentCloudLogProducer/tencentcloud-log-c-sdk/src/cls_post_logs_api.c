#include "cls_post_logs_api.h"
#include <string.h>
#include "cls_sds.h"
#include <curl.h>

int ClsLOGPostAdapt(const char *url,
                    char **header_array,
                    int header_count,
                    const void *data,
                    int data_len);

unsigned int CLS_LOG_GET_TIME();

int cls_log_init(int32_t log_global_flag)
{
    CURLcode ecode;
    if ((ecode = curl_global_init(log_global_flag)) != CURLE_OK)
    {
        return -1;
    }
    return 0;
}
void cls_log_destroy()
{
    curl_global_cleanup();
}

static size_t write_cls_data(void *ptr, size_t size, size_t nmemb, void *stream)
{
    size_t totalLen = size * nmemb;
    cls_sds *buffer = (cls_sds *)stream;
    if (*buffer == NULL)
    {
        *buffer = cls_sdsnewEmpty(256);
    }
    *buffer = cls_sdscpylen(*buffer, ptr, totalLen);
    return totalLen;
}

static size_t cls_header_callback(void *ptr, size_t size, size_t nmemb, void *stream)
{
    size_t totalLen = size * nmemb;
    cls_sds *buffer = (cls_sds *)stream;
    // only copy header start with x-log-
    if (totalLen > 6 && ((memcmp(ptr, "X-Cls-", 6) == 0) ||(memcmp(ptr, "x-cls-", 6) == 0)))
    {
        *buffer = cls_sdscpylen(*buffer, ptr+16, totalLen);
    }
    return totalLen;
}

static const char cls_month_snames[12][4] =
    {
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
static const char cls_day_snames[7][4] =
    {
        "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};

void post_cls_log_result_destroy(post_cls_result *result)
{
    
    if (result != NULL)
    {
        if (result->message != NULL)
        {
            cls_sdsfree(result->message);
        }
        if (result->requestID != NULL)
        {
            cls_sdsfree(result->requestID);
        }
        free(result);
    }
}

void GetClsQueryString(const root_t parameterList,
                    cls_sds queryString)
{
    memset(queryString, 0, strlen(queryString));
    map_t *node;
    for (node = map_first(&parameterList); node; node = map_next(&(node->node)))
    {
        if (node != map_first(&parameterList))
        {
            queryString = cls_sdscat(queryString, "&");
        }
        queryString = cls_sdscat(queryString, node->key);
        queryString = cls_sdscat(queryString, "=");
        unsigned char c_url[strlen(node->val)*3+1];
        memset(c_url,0,strlen(node->val)*3+1);
        urlencode(node->val,c_url);
        queryString = cls_sdscat(queryString, c_url);
    }
}


void PostClsLogsWithLz4(const char *endpoint, const char *accesskeyId, const char *accessKey, const char *topic,cls_lz4_content *buffer, const char *token, cls_log_post_option *option, post_cls_result *rst)
{
    const char *operation = "/structuredlog";
    root_t httpHeader = RB_ROOT;
    if (option == NULL || option->compress_type == 1)
    {
        put(&httpHeader, "x-cls-compress-type", "lz4");
    }
    put(&httpHeader, "Host", (char *)endpoint);
    put(&httpHeader, "Content-Type", "application/x-protobuf");
    put(&httpHeader, "User-Agent", "tencent-log-sdk-ios v1.0.0");

    root_t params = RB_ROOT;
    put(&params, "topic_id", topic);

    //计算签名
    char c_signature[1024];
    signature(accesskeyId, accessKey, "POST", operation, params, httpHeader, 300, c_signature);
    put(&httpHeader, "Authorization", c_signature);
    put(&httpHeader, "x-cls-add-source", "1");
    if(token != NULL){
        put(&httpHeader, "X-Cls-Token", token);
    }
    cls_sds queryString = cls_sdsnewEmpty(1024);
    GetClsQueryString(params, queryString);

    struct curl_slist *headers = NULL;
    map_t *node;
    for (node = map_first(&httpHeader); node; node = map_next(&(node->node)))
    {
        char p[1024];
        memset(p, 0, 1024);
        strcat(p, node->key);
        strcat(p, ":");
        strcat(p, node->val);
        headers = curl_slist_append(headers, p);
    }

    cls_sds queryUrl = cls_sdsnewEmpty(64);
    queryUrl = cls_sdscat(queryUrl, endpoint);
    queryUrl = cls_sdscat(queryUrl, operation);
    if (strlen(queryString) != 0)
    {
        queryUrl = cls_sdscat(queryUrl, "?");
        queryUrl = cls_sdscat(queryUrl, queryString);
    }
    CURL *curl = curl_easy_init();
    if (curl != NULL)
    {

        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_URL, queryUrl);
        curl_easy_setopt(curl, CURLOPT_POST, 1);

        cls_sds body = NULL;
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &body);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cls_data);
        curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, cls_header_callback);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 15);

        if (option != NULL)
        {
            if (option->sockertimeout > 0)
            {
                curl_easy_setopt(curl, CURLOPT_TIMEOUT, option->sockertimeout);
            }
            if (option->connecttimeout > 0)
            {
                curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, option->connecttimeout);
            }
        }
        curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, (void *)buffer->data);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, buffer->length);
        curl_easy_setopt(curl, CURLOPT_FILETIME, 1);
        curl_easy_setopt(curl, CURLOPT_VERBOSE, 0); //打印调试信息
        cls_sds header = cls_sdsnewEmpty(64);
        curl_easy_setopt(curl, CURLOPT_HEADERDATA, &header);
        CURLcode res = curl_easy_perform(curl);
        long http_code;
        if (res == CURLE_OK)
        {
            if ((res = curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code)) != CURLE_OK)
            {
                rst->statusCode = -2;
            }
            else
            {
                rst->statusCode = http_code;
            }
        }
        else
        {
            if (body == NULL)
            {
                body = cls_sdsnew(curl_easy_strerror(res));
            }
            else
            {
                body = cls_sdscpy(body, curl_easy_strerror(res));
            }
            rst->statusCode = -1 * (int)res;
        }
        // header and body 's pointer may be modified in callback (size > 256)

        if (cls_sdslen(header) > 0)
        {
            strncpy(rst->requestID, header, cls_sdslen(header));
        }

        // body will be NULL or a error string(net error or request error)
        if ((body != NULL) && (cls_sdslen(body) != 0)){
            rst->message = (char*)malloc(strlen(body)+1);
            memset(rst->message,0,strlen(body)+1);
            strncpy(rst->message, body, cls_sdslen(body));
        }
        

        curl_slist_free_all(headers); /* free the list again */
        cls_sdsfree(queryString);
        cls_sdsfree(queryUrl);
        cls_sdsfree(header);
        header = NULL;
        cls_sdsfree(body);
        body = NULL;
        curl_easy_cleanup(curl);

        //释放map_t headers
        map_t *nodeFree = NULL;
        for (nodeFree = map_first(&httpHeader); nodeFree; nodeFree = map_first(&httpHeader))
        {
            if (nodeFree)
            {
                rb_erase(&nodeFree->node, &httpHeader);
                map_free(nodeFree);
            }
        }

        //释放map_t headers
        for (nodeFree = map_first(&params); nodeFree; nodeFree = map_first(&params))
        {
            if (nodeFree)
            {
                rb_erase(&nodeFree->node, &params);
                map_free(nodeFree);
            }
        }
    }
}

void SearchClsLogApi(const char *endpoint,root_t httpHeader,root_t params,get_cls_result *result){
    cls_sds queryString = cls_sdsnewEmpty(1024);
    GetClsQueryString(params, queryString);


    struct curl_slist *headers = NULL;
    map_t *node;
    for (node = map_first(&httpHeader); node; node = map_next(&(node->node)))
    {
        char p[1024];
        memset(p, 0, 1024);
        strcat(p, node->key);
        strcat(p, ":");
        strcat(p, node->val);
        headers = curl_slist_append(headers, p);
    }

    cls_sds queryUrl = cls_sdsnewEmpty(64);
    queryUrl = cls_sdscat(queryUrl, endpoint);
    queryUrl = cls_sdscat(queryUrl, "/searchlog");
    if (strlen(queryString) != 0)
    {
        queryUrl = cls_sdscat(queryUrl, "?");
        queryUrl = cls_sdscat(queryUrl, queryString);
    }
    CURL *curl = curl_easy_init();
    if (curl != NULL)
    {

        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_URL, queryUrl);
        curl_easy_setopt(curl, CURLOPT_HTTPGET, 1);
        
        cls_sds header = cls_sdsnewEmpty(64);
        cls_sds body = NULL;
        curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, cls_header_callback);
        curl_easy_setopt(curl, CURLOPT_HEADERDATA, &header);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cls_data);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &body);
        
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 15);
        curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1);
        curl_easy_setopt(curl, CURLOPT_FILETIME, 1);
        curl_easy_setopt(curl, CURLOPT_VERBOSE, 0); //打印调试信息
        
        CURLcode res = curl_easy_perform(curl);
        long http_code;
        if (res == CURLE_OK)
        {
            if ((res = curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code)) != CURLE_OK)
            {
                result->statusCode = -2;
            }
            else
            {
                result->statusCode = http_code;
            }
        }
        else
        {
            if (body == NULL)
            {
                body = cls_sdsnew(curl_easy_strerror(res));
            }
            else
            {
                body = cls_sdscpy(body, curl_easy_strerror(res));
            }
            result->statusCode = -1 * (int)res;
        }
        if (cls_sdslen(header) > 0)
        {
            strncpy(result->requestID, header, cls_sdslen(header));
        }

       // body will be NULL or a error string(net error or request error)
        if ((body != NULL) && (cls_sdslen(body) != 0)){
            result->message = (char*)malloc(strlen(body)+1);
            memset(result->message,0,strlen(body)+1);
            strncpy(result->message, body, cls_sdslen(body));
        }

        curl_slist_free_all(headers); /* free the list again */
        cls_sdsfree(queryString);
        cls_sdsfree(queryUrl);
        cls_sdsfree(header);
        header = NULL;
        cls_sdsfree(body);
        body = NULL;
        curl_easy_cleanup(curl);

        //释放map_t headers
        map_t *nodeFree = NULL;
        for (nodeFree = map_first(&httpHeader); nodeFree; nodeFree = map_first(&httpHeader))
        {
            if (nodeFree)
            {
                rb_erase(&nodeFree->node, &httpHeader);
                map_free(nodeFree);
            }
        }

        //释放map_t headers
        for (nodeFree = map_first(&params); nodeFree; nodeFree = map_first(&params))
        {
            if (nodeFree)
            {
                rb_erase(&nodeFree->node, &params);
                map_free(nodeFree);
            }
        }
    }
    
}

