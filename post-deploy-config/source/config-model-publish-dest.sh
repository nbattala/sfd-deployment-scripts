#!/usr/bin/env bash

source ../../env.properties

oc project $project

#export APPS_DOMAIN=$(oc get ingresscontroller.operator.openshift.io -n openshift-ingress-operator -o jsonpath='{.items[].status.domain}')
#export INGRESS_FQDN="${project}.${APPS_DOMAIN}"
export INGRESS_URL=$(oc get cm -o custom-columns=:.metadata.name | grep sas-shared-config | xargs -n 1 oc get cm -o jsonpath='{.data.SAS_SERVICES_URL}')

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
	curl -s -k -X PUT ${INGRESS_URL}/credentials/domains/SDADockerRegistry -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" -d '
	{
		"domainId"     : "SDADockerRegistry",
		"identityId"   : "sas.detectionDefinition",
		"identityType" : "client",
		"domainType"   : "base64",
		"properties" : {
			"dockerRegistryUserId" : "<base64 encoded value of container registry login ID>"
		},
		"secrets": {
			"dockerRegistryPasswd" : "<base64 encoded value of container registry password>",
		}
	}'

	#create secret for the SDADockerRegistry credential domain (for Intelligent Decisioning)
	curl -s -k -X PUT ${INGRESS_URL}/credentials/domains/SDADockerRegistry -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" -d ' 
	{
		"domainId"     : "SDADockerRegistry",
		"identityId"   : "SDASrRulesEditor",
		"identityType" : "client",
		"domainType"   : "base64",
		"properties" : {
			"dockerRegistryUserId" : "<base64 encoded value of container registry login ID>"
		},
		"secrets": {
			"dockerRegistryPasswd" : "<base64 encoded value of container registry password>",
		}
	}'

	#create publishing destination
	curl -k --location --request POST \
	${INGRESS_URL}/modelPublish/destinations \
	--header "Authorization: Bearer $ACCESS_TOKEN" \
	--header 'Content-Type: application/json' \
	--data '{
		"name"            : "SDADockerRegistry",
		"destinationType" : "privateDocker",
		"description"     : "Created via REST API",
		"properties"      : [{"name"  : "credDomainId",
								"value" : "SDADockerRegistry"},
							{"name"  : "baseRepoUrl",
								"value" : "<container Registry Url"},
							{"name"  : "kubeUrl",
								"value" : "<kube api endpoint"}
							]
	}'
}

config-model-publish-dest