#!/usr/bin/env bash
source env.properties
oc project $project

bankProject=cp-3353070
bankImagePullSecret=registry-nonprod
#escape /
bankCrEndPoint='registry-nonprod.sdi.corp.bankofamerica.com\/47231\/sas'
bankNsGroupId=1003310000
bankIngressHost=$bankProject.apps.useast15.bofa.com
#bankRwxSC=odf-encrypted-rwx
#bankRwoSC=odf-encrypted-rwo


imagePullSecret=$(oc -n $project get secrets -o custom-columns=":metadata.name" | grep sas-image-pull-secrets)
nsGroupId=$(oc describe ns $project | grep sa.scc.supplemental-groups | awk '{print $2}' | awk -F '/' '{print $1}')
APPS_DOMAIN=$(oc get ingresscontroller.operator.openshift.io -n openshift-ingress-operator -o jsonpath='{.items[].status.domain}')
ingressHost="${project}.${APPS_DOMAIN}"

sed -i "s/${project}/${bankProject}/g" site.yaml
sed -i "s/${imagePullSecret}/${bankImagePullSecret}/g" site.yaml
sed -i "s/cr.sas.com\/viya-4-x64_oci_linux_2-docker/${bankCrEndPoint}/g" site.yaml
sed -i "s/${nsGroupId}/${bankNsGroupId}/g" site.yaml
sed -i "s/${ingressHost}/${bankIngressHost}/g" site.yaml