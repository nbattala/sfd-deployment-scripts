#!/usr/bin/env bash

export INGRESS_URL=$(oc get cm -o custom-columns=:.metadata.name | grep sas-shared-config | xargs -n 1 oc get cm -o jsonpath='{.data.SAS_SERVICES_URL}')

configure-sfd-with-redis () {
    echo "Entering ${FUNCNAME[0]}"
    redisHost=${1}
    redisPort=${2}
    [ ${3} != "null" ] && redisUser=${3} || redisUser="default"
    [ ${4} != "null" ] && redisPassword=${4}
    echo "configuring SAS Fraud Decisioning runtime"
    kubectl -n ${VIYA_NS} set env deployment/sas-detection -c sas-detection SAS_DETECTION_REDIS_HOST=${redisHost}
    kubectl -n ${VIYA_NS} set env deployment/sas-detection -c sas-detection SAS_DETECTION_REDIS_PORT=${redisPort}
    kubectl -n ${VIYA_NS} set env deployment/sas-detection -c sas-detection SAS_DETECTION_REDIS_KEY_PREFIX="SASODE|0"
    kubectl -n ${VIYA_NS} set env deployment/sas-detection -c sas-detection SAS_DETECTION_REDIS_POOL_SIZE="10"
    kubectl -n ${VIYA_NS} set env deployment/sas-detection -c sas-detection SAS_DETECTION_REDIS_AUTH_USER=${redisUser}
    kubectl -n ${VIYA_NS} set env deployment/sas-detection -c sas-detection SAS_DETECTION_REDIS_AUTH_PASS=${redisPassword}
    #configure sas-sda-scr with Redis if exists
    if kubectl -n ${VIYA_NS} get deployment sas-detection -o jsonpath='{.spec.template.spec.containers[*].name}' | grep -q 'sas-sda-scr'; then
        kubectl -n ${VIYA_NS} set env deployment/sas-detection -c sas-sda-scr SAS_REDIS_HOST=${redisHost}
        kubectl -n ${VIYA_NS} set env deployment/sas-detection -c sas-sda-scr SAS_REDIS_PORT=${redisPort}
        kubectl -n ${VIYA_NS} set env deployment/sas-detection -c sas-sda-scr SAS_REDIS_KEY_PREFIX="SAS|0"
        kubectl -n ${VIYA_NS} set env deployment/sas-detection -c sas-sda-scr SAS_REDIS_AUTH_USER=${redisUser}
        kubectl -n ${VIYA_NS} set env deployment/sas-detection -c sas-sda-scr SAS_REDIS_AUTH_PASS=${redisPassword}
    fi
    echo "configuring SAS Fraud Decisioning designtime"
    get-ingress-fqdn
    ACCESS_TOKEN=$(curl -k -X POST ${INGRESS_URL}/SASLogon/oauth/token -H 'Accept: application/json' -H 'Content-type: application/x-www-form-urlencoded' -H 'Authorization: Basic c2FzLmVjOg==' -d 'grant_type=password&username=sasboot&password=Password123'|jq -r '.access_token')
    ### SECTION ############################################
    echo "Update Redis Values in Consul"
    ########################################################
    curl -k -X POST ${INGRESS_URL}/configuration/configurations \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/vnd.sas.collection+json" \
     -d '
     {
          "version": 2,
          "items": [
          {
               "metadata": {
                    "services": [
                         "listData"
                    ],
               "isDefault": false,
               "mediaType": "application/vnd.sas.configuration.config.sas.listdata.redis+json;version=4",
               "tenant": null
               },
               "address": "'${redisHost}:${redisPort}'",
               "password": "",
               "db": 0,
               "useSSL": false,
               "serverFQDN": ""
          }
          ]
     }'| jq

    ### SECTION ############################################
    echo "Add List Data Redis Credentials"
    ########################################################
    redisPasswordB64=$(echo -n ${redisPassword} | base64)
    #echo "base64 redis passwd: $redisPasswordB64"
    declare -a arr=("SDASrRulesEditor" "SDAJrRulesEditor" "SDARulesEditor" "SDASystemAdmin")
    for i in "${arr[@]}"
    do 
        #curl -k --trace - --location --request PUT https://${INGRESS_FQDN}/credentials/domains/ListDataRedis/groups/${i} \
        curl -k --request PUT ${INGRESS_URL}/credentials/domains/ListDataRedis/groups/${i} \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{
        "domainId": "ListDataRedis",
        "identityId": "'${i}'",
        "identityType": "group",
        "domainType": "password",
            "properties": {
                "userId": "'${redisUser}'"
            },
            "secrets": {
                "password": "'${redisPasswordB64}'"
            }
        }'
    done
    #add client credentials - starting 2023.11
#    curl -k --location --request PUT https://${INGRESS_FQDN}/credentials/domains/ListDataRedis/clients/sas.detectionDefinition \
#    -H "Authorization: Bearer $ACCESS_TOKEN" \
#    -H "Content-Type: application/json" \
#    --data '{
#    "domainId": "ListDataRedis",
#    "identityId": "sas.detectionDefinition",
#    "identityType": "client",
#    "domainType": "password",
#    "properties": {
#        "userId": "'${redisUser}'"
#    },
#    "secrets": {
#        "password": "'${redisPasswordB64}'"
#    }
#    }'
#
    echo "Leaving ${FUNCNAME[0]}"
}

configure-sfd-with-redis $redishostName $redishostPort $user $pwd