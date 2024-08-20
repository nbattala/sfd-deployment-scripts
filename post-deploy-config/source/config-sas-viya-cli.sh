#!/usr/bin/env bash

export APPS_DOMAIN=$(oc get ingresscontroller.operator.openshift.io -n openshift-ingress-operator -o jsonpath='{.items[].status.domain}')
export INGRESS_FQDN="${project}.${APPS_DOMAIN}"


./sas-viya profile init --sas-endpoint https://${INGRESS_FQDN} 
