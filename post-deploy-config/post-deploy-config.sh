#!/usr/bin/env bash

chmod +x ../resources/tools/*
export PATH=$PATH:../resources/tools
source ../properties.env
chmod +x ./source/*.sh
fn_dir=source
if [ -d "$fn_dir" ]; then
    for file in "$fn_dir"/*.sh; do
        [ -r "$file" ] && source "$file"
    done
else
    echo 'ERROR: directory "source" not found in current directory'
    exit 1
fi
export INGRESS_URL=$(oc get cm -o custom-columns=:.metadata.name | grep sas-shared-config | xargs -n 1 oc get cm -o jsonpath='{.data.SAS_SERVICES_URL}')
export ACCESS_TOKEN=$(curl -k -X POST ${INGRESS_URL}/SASLogon/oauth/token -H 'Accept: application/json' -H 'Content-type: application/x-www-form-urlencoded' -H 'Authorization: Basic c2FzLmVjOg==' -d 'grant_type=password&username=sasboot&password=Password123'|jq -r '.access_token')

#echo $ACCESS_TOKEN
#export kubeUrl=$(oc project | awk '{print $6}' | cut -d "\"" -f 2)
export kubeUrl=$(oc project | grep -oh "http[^ ]*" | cut -d "\"" -f 1)
export imageRegistryHost=$(echo ${imageRegistry} | cut -d '/' -f 1)
export dockerUser=$(oc get secret $imagePullSecret -o=jsonpath={.data."\.dockerconfigjson"} | base64 -d | jq -r .auths.\"$imageRegistryHost\".username)
export dockerUserB64=$(echo -n $dockerUser | base64)
#echo -n "$dockerUserB64" | base64 -d
export dockerPwd=$(oc get secret $imagePullSecret -o=jsonpath={.data."\.dockerconfigjson"} | base64 -d | jq -r .auths.\"$imageRegistryHost\".password)
export dockerPwdB64=$(echo -n $dockerPwd | base64)
#echo -n "$dockerPwdB64" | base64 -d
#################################################################


#config-sso-oauth disable
#config-model-publish-dest
#config-sfd-designtime
#config-sfd-rules-studio
config-query-internal-postgres
