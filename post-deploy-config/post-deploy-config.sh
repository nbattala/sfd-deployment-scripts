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
echo "please enter password of sasboot":
read -rs sasbootPwd
export ACCESS_TOKEN=$(curl -k -X POST ${INGRESS_URL}/SASLogon/oauth/token -H 'Accept: application/json' -H 'Content-type: application/x-www-form-urlencoded' -H 'Authorization: Basic c2FzLmVjOg==' -d "grant_type=password&username=sasboot&password=${sasbootPwd}"|jq -r '.access_token')
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


#config-sso-oauth 
#config-model-publish-dest
config-sfd-designtime
#config-sfd-rules-studio
#config-query-internal-postgres "SELECT * FROM logon.identity_provider"
#config-query-internal-postgres "DELETE FROM logon.identity_provider WHERE id='6feb707e-05b8-4d85-adb6-63ddede40411'; COMMIT;"
#config-internal-redis
#config-license-renew /mnt/c/Users/nabatt/myWorkdir/downloads/downloads.2025.01/SASViyaV4_9D1XQ4_stable_2025.02_license_17405295261
