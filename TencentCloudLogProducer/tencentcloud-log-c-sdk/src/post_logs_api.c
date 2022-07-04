#include "post_logs_api.h"
#include <string.h>
#include "sds.h"
#include <curl.h>

int LOGPostAdapt(const char *url,
                    char **header_array,
                    int header_count,
                    const void *data,
                    int data_len);

unsigned int LOG_GET_TIME();

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

static size_t write_data(void *ptr, size_t size, size_t nmemb, void *stream)
{
    size_t totalLen = size * nmemb;
    sds *buffer = (sds *)stream;
    if (*buffer == NULL)
    {
        *buffer = sdsnewEmpty(256);
    }
    *buffer = sdscpylen(*buffer, ptr, totalLen);
    return totalLen;
}

static size_t header_callback(void *ptr, size_t size, size_t nmemb, void *stream)
{
    size_t totalLen = size * nmemb;
    sds *buffer = (sds *)stream;
    // only copy header start with x-log-
    if (totalLen > 6 && ((memcmp(ptr, "X-Cls-", 6) == 0) ||(memcmp(ptr, "x-cls-", 6) == 0)))
    {
        *buffer = sdscpylen(*buffer, ptr+16, totalLen);
    }
    return totalLen;
}

static const char cls_month_snames[12][4] =
    {
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
static const char cls_day_snames[7][4] =
    {
        "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};

void post_log_result_destroy(post_result *result)
{
    
    if (result != NULL)
    {
        if (result->message != NULL)
        {
            sdsfree(result->message);
        }
        if (result->requestID != NULL)
        {
            sdsfree(result->requestID);
        }
        free(result);
    }
}

void GetQueryString(const root_t parameterList,
                    sds queryString)
{
    memset(queryString, 0, strlen(queryString));
    map_t *node;
    for (node = map_first(&parameterList); node; node = map_next(&(node->node)))
    {
        if (node != map_first(&parameterList))
        {
            queryString = sdscat(queryString, "&");
        }
        queryString = sdscat(queryString, node->key);
        queryString = sdscat(queryString, "=");
        unsigned char c_url[strlen(node->val)*3+1];
        memset(c_url,0,strlen(node->val)*3+1);
        urlencode(node->val,c_url);
        queryString = sdscat(queryString, c_url);
    }
}


post_result *PostLogsWithLz4(const char *endpoint, const char *accesskeyId, const char *accessKey, const char *topic,lz4_content *buffer, const char *token, log_post_option *option)
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

    if(token != NULL){
        put(&httpHeader, "X-Cls-Token", token);
    }
    sds queryString = sdsnewEmpty(1024);
    GetQueryString(params, queryString);

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

    sds queryUrl = sdsnewEmpty(64);
    queryUrl = sdscat(queryUrl, endpoint);
    queryUrl = sdscat(queryUrl, operation);
    if (strlen(queryString) != 0)
    {
        queryUrl = sdscat(queryUrl, "?");
        queryUrl = sdscat(queryUrl, queryString);
    }
    CURL *curl = curl_easy_init();
    post_result *result = (post_result *)malloc(sizeof(post_result));
    memset(result, 0, sizeof(post_result));
    if (curl != NULL)
    {

        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_URL, queryUrl);
        curl_easy_setopt(curl, CURLOPT_POST, 1);

        sds body = NULL;
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &body);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_data);
        curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, header_callback);
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
        sds header = sdsnewEmpty(64);
        curl_easy_setopt(curl, CURLOPT_HEADERDATA, &header);
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
                body = sdsnew(curl_easy_strerror(res));
            }
            else
            {
                body = sdscpy(body, curl_easy_strerror(res));
            }
            result->statusCode = -1 * (int)res;
        }
        // header and body 's pointer may be modified in callback (size > 256)

        if (sdslen(header) > 0)
        {
            result->requestID = header;
        }
        else
        {
            sdsfree(header);
            header = NULL;
        }

        // body will be NULL or a error string(net error or request error)
        result->message = body;

        curl_slist_free_all(headers); /* free the list again */
        sdsfree(queryString);
        sdsfree(queryUrl);
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

    return result;
}

void SearchLogApi(const char *endpoint,root_t httpHeader,root_t params,get_result* result){
    sds queryString = sdsnewEmpty(1024);
    GetQueryString(params, queryString);


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

    sds queryUrl = sdsnewEmpty(64);
    queryUrl = sdscat(queryUrl, endpoint);
    queryUrl = sdscat(queryUrl, "/searchlog");
    if (strlen(queryString) != 0)
    {
        queryUrl = sdscat(queryUrl, "?");
        queryUrl = sdscat(queryUrl, queryString);
    }
    CURL *curl = curl_easy_init();
    if (curl != NULL)
    {

        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_URL, queryUrl);
        curl_easy_setopt(curl, CURLOPT_HTTPGET, 1);
        
        sds header = sdsnewEmpty(64);
        sds body = NULL;
        curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, header_callback);
        curl_easy_setopt(curl, CURLOPT_HEADERDATA, &header);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_data);
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
                body = sdsnew(curl_easy_strerror(res));
            }
            else
            {
                body = sdscpy(body, curl_easy_strerror(res));
            }
            result->statusCode = -1 * (int)res;
        }
        if (sdslen(header) > 0)
        {
            result->requestID = header;
        }
        else
        {
            sdsfree(header);
            header = NULL;
        }

       // body will be NULL or a error string(net error or request error)
        result->message = body;


        curl_slist_free_all(headers); /* free the list again */
        sdsfree(queryString);
        sdsfree(queryUrl);
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

