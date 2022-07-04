//
// Created by herrylv on 06/5/2022
//
#include "log_producer_client.h"
#include "log_producer_manager.h"
#include "cls_log.h"
#include "utils.h"
#include "post_logs_api.h"
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>

static uint32_t s_init_flag = 0;
static int s_last_result = 0;
static int search_init_api_flag = 0;

unsigned int LOG_GET_TIME();

typedef struct
{

    ProducerManager *producermgr;
    ProducerConfig *producerconf;

} PrivateProducerClient;

struct clslogproducer
{
    clslogproducerclient *ancestor;
};

int  ClsLogProducerInit()
{
    // if already init, just return s_last_result
    if (s_init_flag == 1)
    {
        return s_last_result;
    }
    s_init_flag = 1;
    if (0 != cls_log_init(LOG_GLOBAL_ALL))
    {
        s_last_result = LOG_PRODUCER_INVALID;
    }
    else
    {
        s_last_result = LOG_PRODUCER_OK;
    }
    return s_last_result;
}

void ClsLogProducerDestroy()
{
    if (s_init_flag == 0)
    {
        return;
    }
    s_init_flag = 0;
    cls_log_destroy();
}

clslogproducer *ConstructorClsLogProducer(ProducerConfig *config, SendCallBackFunc callbackfunc, void *user_param)
{
    if (!is_valid(config))
    {
        return NULL;
    }
    clslogproducer *producer = (clslogproducer *)malloc(sizeof(clslogproducer));
    clslogproducerclient *producerclient = (clslogproducerclient *)malloc(sizeof(clslogproducerclient));
    PrivateProducerClient *privateclient = (PrivateProducerClient *)malloc(sizeof(PrivateProducerClient));
    producerclient->private_client = privateclient;
    privateclient->producerconf = config;
    privateclient->producermgr = ConstructorProducerManager(config);
    privateclient->producermgr->callbackfunc = callbackfunc;
    privateclient->producermgr->user_param = user_param;

    cls_debug_log("create producer client success, topic : %s", config->topic);
    producerclient->efficient = true;
    producer->ancestor = producerclient;
    return producer;
}

void DestructorClsLogProducer(clslogproducer *producer)
{
    if (producer == NULL)
    {
        return;
    }
    clslogproducerclient *client = producer->ancestor;
    client->efficient = false;
    PrivateProducerClient *client_private = (PrivateProducerClient *)client->private_client;
    destroy_log_producer_manager(client_private->producermgr);
    DestroyClsLogProducerConfig(client_private->producerconf);
    free(client_private);
    free(client);
    free(producer);
}

extern clslogproducerclient *GetClsLogProducer(clslogproducer *producer, const char *config_name)
{
    if (producer == NULL)
    {
        return NULL;
    }
    return producer->ancestor;
}

int
PostClsLog(clslogproducerclient *client,
           int64_t logtime,
                                                int32_t pair_count, char **keys,
                                                int32_t *key_lens, char **values,
                                                int32_t *value_lens, int flush)
{
    if (client == NULL || !client->efficient)
    {
        return LOG_PRODUCER_INVALID;
    }

    ProducerManager *manager = ((PrivateProducerClient *)client->private_client)->producermgr;
    return log_producer_manager_add_log(manager, logtime,pair_count, keys, key_lens, values, value_lens, flush, -1);
}

//search log
int ClsSearchLog(const char *region,const char *secretid, const char* secretkey,const char* logsetid,const char **topicids,const int topicidslens,const char* starttime,const char* endtime,const char* query,size_t limit,const char* context,const char* sort,get_result* result){
    //参数校验
    int iRet = SearchLogCheckParam(region,secretid, secretkey,logsetid,topicids, topicidslens, starttime, endtime,query, limit,sort);
    if(iRet != 0){
        result->statusCode = iRet;
        return iRet;
    }
    
    //构造Query数据
    root_t params = RB_ROOT;
    put(&params, "logset_id", logsetid);
    char *strtopics = malloc(4096);
    memset(strtopics,0,4096);
    arr_to_string(topicids, topicidslens, strtopics);
    put(&params, "topic_ids", strtopics);
    put(&params, "start_time", starttime);
    put(&params, "end_time", endtime);
    put(&params, "query_string", query);
    char slimit[10];
    memset(slimit,0,sizeof(slimit));
    sprintf(slimit, " %d" , limit);
    put(&params, "limit", slimit);
    if(context != NULL){
        put(&params, "context", context);
    }
    if(sort != NULL){
        put(&params, "sort", sort);
    }
    
    //构造header数据
    root_t httpHeader = RB_ROOT;
    put(&httpHeader, "Host", (char *)region);
    char c_signature[1024];
    signature(secretid, secretkey, "GET", "/searchlog", params, httpHeader, 300, c_signature);
    put(&httpHeader, "Authorization", c_signature);
    
    //发起请求
    SearchLogApi(region, httpHeader, params,result);
    free(strtopics);
    return 0;
}

int SearchLogCheckParam(const char *region,const char *secretid, const char* secretkey,const char* logsetid,const char **topicids,const int topicidslens,const char* starttime,const char* endtime,const char* query,size_t limit,const char* sort){
    if(strlen(region) == 0 || strlen(secretid) == 0 ||strlen(secretkey) == 0||strlen(logsetid) == 0||topicids == NULL ||topicidslens <= 0||strlen(starttime) == 0||strlen(endtime) == 0 ||limit == 0){
        return -1;
    }
    char *tmpsort = (char*)malloc(strlen(sort)+1);
    memset(tmpsort,0,strlen(sort)+1);
    strlowr(sort,tmpsort);
    if(sort != NULL && (strncmp(tmpsort,"asc",3) != 0)&&(strncmp(tmpsort,"desc",4) != 0)){
        return -1;
    }
    free(tmpsort);
    return 0;
}

int ClsLogSearchLogInit()
{
    if (search_init_api_flag == 1)
    {
        return s_last_result;
    }
    search_init_api_flag = 1;
    if (0 != cls_log_init(LOG_GLOBAL_ALL))
    {
        s_last_result = LOG_PRODUCER_INVALID;
    }
    else
    {
        s_last_result = LOG_PRODUCER_OK;
    }
    return s_last_result;
}

void ClsLogSearchLogDestroy()
{
    if (search_init_api_flag == 0)
    {
        return;
    }
    search_init_api_flag = 0;
    cls_log_destroy();
}
