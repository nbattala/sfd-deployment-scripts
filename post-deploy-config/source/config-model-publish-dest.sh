#!/usr/bin/env bash

source ../../env.properties

oc project $project

#export APPS_DOMAIN=$(oc get ingresscontroller.operator.openshift.io -n openshift-ingress-operator -o jsonpath='{.items[].status.domain}')
#export INGRESS_FQDN="${project}.${APPS_DOMAIN}"
export INGRESS_URL=$(oc get cm -o custom-columns=:.metadata.name | grep sas-shared-config | xargs -n 1 oc get cm -o jsonpath='{.data.SAS_SERVICES_URL}')
export dockerUrl=acrce34aa65ifgei.azurecr.io/sas
export dockerUser=acrce34aa65ifgei
echo "Please enter password for docker user $dockerUser:"
read dockerPwd

export dockerUserB64=$(echo -n $dockerUser | base64)
export dockerPwdB64=$(echo -n $dockerPwd | base64)
export kubeUrl=$(oc project | awk '{print $6}' | cut -d "\"" -f 2)

config-model-publish-dest () {
	echo "Entering ${FUNCNAME[0]}"
	#obtain access token
	ACCESS_TOKEN=$(curl -k -X POST ${INGRESS_URL}/SASLogon/oauth/token -H 'Accept: application/json' -H 'Content-type: application/x-www-form-urlencoded' -H 'Authorization: Basic c2FzLmVjOg==' -d 'grant_type=password&username=sasboot&password=Password123'|jq -r '.access_token')
	#create SDADockerRegistry credential domain
	curl -s -k -X PUT ${INGRESS_URL}/credentials/domains/SDADockerRegistry -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" -d ' 
	{
		"id"          : "SDADockerRegistry",
		"description" : "SDADockerRegistry Domain ID and Publishing Destination",
		"type"        : "base64"
	}'

	#create secret for the SDADockerRegistry credential domain (for SFD)
	#prepare payload for SFD
    printf "%s" \ { \
    \"identityId\"    : \"sas.detectionDefinition\",    \
    \"identityType\"  : \"client\",                 \
    \"domainId\"   : \"SDADockerRegistry\",         \
    \"domainType\"    : \"base64\",                 \
    \"properties\":{\"dockerRegistryUserId\":\"${dockerUserB64}\"},        \
    \"secrets\":{\"dockerRegistryPasswd\":\"${dockerPwdB64}\"}    \
    }\
    |jq| tee /tmp/.SDADockerRegistry-sfd.json > /dev/null
	curl -s -k -X PUT ${INGRESS_URL}/credentials/domains/SDADockerRegistry/clients/sas.detectionDefinition -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" -d @/tmp/.SDADockerRegistry-sfd.json

	#create secret for the SDADockerRegistry credential domain (for Intelligent Decisioning)
	#prepare payload for ID
    printf "%s" \ { \
    \"identityId\"    : \"SDASrRulesEditor\",    \
    \"identityType\"  : \"group\",                 \
    \"domainId\"   : \"SDADockerRegistry\",         \
    \"domainType\"    : \"base64\",                 \
    \"properties\":{\"dockerRegistryUserId\":\"${dockerUserB64}\"},        \
    \"secrets\":{\"dockerRegistryPasswd\":\"${dockerPwdB64}\"}    \
    }\
    |jq| tee /tmp/.SDADockerRegistry-id.json > /dev/null
	curl -s -k -X PUT ${INGRESS_URL}/credentials/domains/SDADockerRegistry/groups/SDASrRulesEditor -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" -d @/tmp/.SDADockerRegistry-id.json

	#create publishing destination
	#prepare payload for pub destination
    printf "%s" \ { \
    \"name\"    :   \"SDADockerRegistry\",                   \
    \"destinationType\" : \"privateDocker\",                         \
    \"description\" :   \"Docker repository for SDA create by REST API\",       \
    \"properties\"  : [{\"name\": \"baseRepoUrl\", \"value\": \"${dockerUrl}\"},                       \
                       {\"name\": \"credDomainId\", \"value\": \"SDADockerRegistry\"},             \
                       {\"name\": \"kubeUrl\", \"value\": \"${kubeUrl}\"}                   \
                      ] \
    }\
    |jq| tee /tmp/.SDAConfigPubDest.json > /dev/null
	curl -k --location -X POST  ${INGRESS_URL}/modelPublish/destinations --header "Authorization: Bearer $ACCESS_TOKEN" --header 'Content-Type: application/json' -d @/tmp/.SDAConfigPubDest.json
}

config-model-publish-dest
