#!/usr/bin/env bash

config-sfd-designtime () {
    printf "Entering ${FUNCNAME[0]}\n"
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
               "useSSL": '${redisTlsEnabled}',
               "serverFQDN": "'${redisServerDomain}'"
          }
          ]
     }'| jq

    ### SECTION ############################################
    echo "Add List Data Redis Credentials"
    ########################################################
    redisPasswordB64=$(echo -n ${redisPassword} | base64)
    echo "base64 redis passwd: $redisPasswordB64"
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
}