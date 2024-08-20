#!/usr/bin/env bash

source ../../env.properties

oc project $project

export APPS_DOMAIN=$(oc get ingresscontroller.operator.openshift.io -n openshift-ingress-operator -o jsonpath='{.items[].status.domain}')
export INGRESS_FQDN="${project}.${APPS_DOMAIN}"

config-ad-connection () {
    echo "Entering ${FUNCNAME[0]}"
    #obtain access token
    ACCESS_TOKEN=$(curl -k -X POST https://${INGRESS_FQDN}/SASLogon/oauth/token -H 'Accept: application/json' -H 'Content-type: application/x-www-form-urlencoded' -H 'Authorization: Basic c2FzLmVjOg==' -d 'grant_type=password&username=sasboot&password=Password123'|jq -r '.access_token')
}

config-ad-connection