#!/usr/bin/env bash


config-model-publish-dest () {
	echo "Entering ${FUNCNAME[0]}"
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
    \"properties\"  : [{\"name\": \"baseRepoUrl\", \"value\": \"${imageRegistry}\"},                       \
                       {\"name\": \"credDomainId\", \"value\": \"SDADockerRegistry\"},             \
                       {\"name\": \"kubeUrl\", \"value\": \"${kubeUrl}\"}                   \
                      ] \
    }\
    |jq| tee /tmp/.SDAConfigPubDest.json > /dev/null
	curl -k --location -X POST  ${INGRESS_URL}/modelPublish/destinations --header "Authorization: Bearer $ACCESS_TOKEN" --header 'Content-Type: application/json' -d @/tmp/.SDAConfigPubDest.json
}