//
// Created by herrylv on 06/5/2022
//
#include "cls_log_producer_client.h"
#include "cls_log_producer_manager.h"
#include "cls_log_persistent_manager.h"
#include "cls_log.h"
#include "cls_utils.h"
#include "cls_post_logs_api.h"
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>

static uint32_t s_init_flag = 0;
static int s_last_result = 0;
static int search_init_api_flag = 0;

unsigned int CLS_LOG_GET_TIME();

typedef struct
{

    ClsProducerManager *producermgr;
    ClsProducerConfig *producerconf;
    cls_log_recovery_manager * persistent_manager;
} ClsPrivateProducerClient;

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
    if (0 != cls_log_init(CLS_LOG_GLOBAL_ALL))
    {
        s_last_result = CLS_LOG_PRODUCER_INVALID;
    }
    else
    {
        s_last_result = CLS_LOG_PRODUCER_OK;
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

clslogproducer *ConstructorClsLogProducer(ClsProducerConfig *config, ClsSendCallBackFunc callbackfunc, void *user_param)
{
    if (!is_cls_valid(config))
    {
        return NULL;
    }
    clslogproducer *producer = (clslogproducer *)malloc(sizeof(clslogproducer));
    clslogproducerclient *producerclient = (clslogproducerclient *)malloc(sizeof(clslogproducerclient));
    ClsPrivateProducerClient *privateclient = (ClsPrivateProducerClient *)malloc(sizeof(ClsPrivateProducerClient));
    producerclient->private_client = privateclient;
    privateclient->producerconf = config;
    privateclient->producermgr = ConstructorClsProducerManager(config);
    privateclient->producermgr->callbackfunc = callbackfunc;
    privateclient->producermgr->user_param = user_param;
    
    privateclient->persistent_manager = create_cls_log_recovery_manager(config);
    if (privateclient->persistent_manager != NULL)
    {
        privateclient->producermgr->uuid_user_param = privateclient->persistent_manager;
        privateclient->producermgr->send_done_persistent_function = on_cls_log_recovery_manager_send_done_uuid;
        int recoverRst = log_persistent_manager_recover_cls_log(privateclient->persistent_manager, privateclient->producermgr);
        if (recoverRst != 0)
        {
            cls_error_log("topic %s, recover log persistent manager failed, result %d",
                          config->topic,
                          recoverRst);
        }
        else
        {
            cls_info_log("topic %s, recover log persistent manager success",
                          config->topic);
        }
    }

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
    ClsPrivateProducerClient *client_private = (ClsPrivateProducerClient *)client->private_client;
    destroy_cls_log_producer_manager(client_private->producermgr);
    DestroyClsLogProducerConfig(client_private->producerconf);
    destroy_cls_log_recovery_manager(client_private->persistent_manager);
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
PostClsLogWithPersistent(clslogproducerclient *client,
                                                int64_t logtime,
                                                int32_t pair_count, char **keys,
                                                int32_t *key_lens, char **values,
                                                int32_t *value_lens, int flush, int64_t logSize)
{
    if (client == NULL || !client->efficient)
    {
        return CLS_LOG_PRODUCER_INVALID;
    }

    ClsProducerManager *producermgr = ((ClsPrivateProducerClient *)client->private_client)->producermgr;
    if (producermgr->totalBufferSize > producermgr->producerconf->maxBufferBytes)
    {
        return CLS_LOG_PRODUCER_DROP_ERROR;
    }
    cls_log_recovery_manager * persistent_manager = ((ClsPrivateProducerClient *)client->private_client)->persistent_manager;
    if (persistent_manager == NULL || persistent_manager->is_invalid == 1){
        return 10010;
    }
    if (!log_recovery_manager_is_buffer_enough(persistent_manager, logSize))
    {
        printf("error totalBufferSize:%lld|maxBufferBytes:%lld\n",producermgr->totalBufferSize,producermgr->producerconf->maxBufferBytes);
        return 10012;
    }
    pthread_mutex_lock(producermgr->lock);
    pthread_mutex_lock(persistent_manager->lock);
    if (producermgr->builder == NULL)
    {
        if (CheckClsLogQueueIsFull(producermgr->loggroup_queue))
        {
            pthread_mutex_unlock(producermgr->lock);
            pthread_mutex_unlock(persistent_manager->lock);
            return 10011;
        }
        int32_t now_time = time(NULL);
        producermgr->builder = GenerateClsLogGroup();
        producermgr->firstLogTime = now_time;
        producermgr->builder->private_value = producermgr;
    }
    InnerAddClsLog(producermgr->builder, logtime, pair_count, keys, key_lens, values, value_lens);

    int32_t nowTime = time(NULL);
    if (flush == 0 && producermgr->builder->loggroup_size < producermgr->producerconf->logBytesPerPackage && nowTime - producermgr->firstLogTime < producermgr->producerconf->packageTimeoutInMS / 1000 && producermgr->builder->grp->logs_count < producermgr->producerconf->logCountPerPackage)
    {
        pthread_mutex_unlock(producermgr->lock);
        pthread_mutex_unlock(persistent_manager->lock);
        return CLS_LOG_PRODUCER_OK;
    }

    int rst = log_recovery_manager_save_cls_log(persistent_manager, producermgr->builder);
    if (rst != CLS_LOG_PRODUCER_OK)
    {
        pthread_mutex_unlock(producermgr->lock);
        pthread_mutex_unlock(persistent_manager->lock);
        return 10013;
    }
    
    cls_log_group_builder *builder = producermgr->builder;
    builder->end_uuid = builder->start_uuid= persistent_manager->checkpoint.now_log_uuid - 1;
    int ret = CLS_LOG_PRODUCER_OK;
    producermgr->builder = NULL;
    size_t loggroup_size = builder->loggroup_size;
    cls_debug_log("try push loggroup to flusher, size : %d, log count %d", (int)builder->loggroup_size, (int)builder->grp->logs_count);
    int status = cls_log_queue_push(producermgr->loggroup_queue, builder);
    if (status != 0)
    {
        cls_error_log("try push loggroup to flusher failed, force drop this log group, error code : %d", status);
        ret = 10014;
        cls_log_group_destroy(builder);
    }
    else
    {
        producermgr->totalBufferSize += loggroup_size;
        pthread_cond_signal(producermgr->triger_cond);
    }
    pthread_mutex_unlock(producermgr->lock);
    pthread_mutex_unlock(persistent_manager->lock);
    return ret;
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
        return CLS_LOG_PRODUCER_INVALID;
    }

    ClsProducerManager *manager = ((ClsPrivateProducerClient *)client->private_client)->producermgr;
    return cls_log_producer_manager_add_log(manager, logtime,pair_count, keys, key_lens, values, value_lens, flush, -1);
}

//search log
int ClsSearchLog(const char *region,const char *secretid, const char* secretkey,const char* logsetid,const char **topicids,const int topicidslens,const char* starttime,const char* endtime,const char* query,size_t limit,const char* context,const char* sort,get_cls_result *result){
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
    cls_arr_to_string(topicids, topicidslens, strtopics);
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
    SearchClsLogApi(region, httpHeader, params,result);
    free(strtopics);
    return 0;
}

int SearchLogCheckParam(const char *region,const char *secretid, const char* secretkey,const char* logsetid,const char **topicids,const int topicidslens,const char* starttime,const char* endtime,const char* query,size_t limit,const char* sort){
    if(strlen(region) == 0 || strlen(secretid) == 0 ||strlen(secretkey) == 0||strlen(logsetid) == 0||topicids == NULL ||topicidslens <= 0||strlen(starttime) == 0||strlen(endtime) == 0 ||limit == 0){
        return -1;
    }
    if(sort != NULL){
        char *tmpsort = (char*)malloc(strlen(sort)+1);
        memset(tmpsort,0,strlen(sort)+1);
        strlowr(sort,tmpsort);
        if((strncmp(tmpsort,"asc",3) != 0)&&(strncmp(tmpsort,"desc",4) != 0)){
            return -1;
        }
        free(tmpsort);
    }
    return 0;
}

int ClsLogSearchLogInit()
{
    if (search_init_api_flag == 1)
    {
        return s_last_result;
    }
    search_init_api_flag = 1;
    if (0 != cls_log_init(CLS_LOG_GLOBAL_ALL))
    {
        s_last_result = CLS_LOG_PRODUCER_INVALID;
    }
    else
    {
        s_last_result = CLS_LOG_PRODUCER_OK;
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
