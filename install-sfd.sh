#!/usr/bin/env bash
source properties.env

oc project $project

#Apply and bind SCCs
oc apply -f resources/scc/cas-server-scc-host-launch.yaml
oc -n $project adm policy add-scc-to-user sas-cas-server-host -z sas-cas-server
oc apply -f resources/scc/sas-microanalytic-score-scc.yaml
oc -n $project adm policy add-scc-to-user sas-microanalytic-score -z sas-microanalytic-score
oc apply -f resources/scc/sas-detection-definition-scc.yaml
oc -n $project adm policy add-scc-to-user sas-detection-definition -z sas-detection-definition 
oc apply -f resources/scc/sas-model-repository-scc.yaml
oc -n $project adm policy add-scc-to-user sas-model-repository -z sas-model-repository
oc apply -f resources/scc/sas-opendistro-scc-modified-for-sysctl-transformer.yaml
oc -n $project adm policy add-scc-to-user sas-opendistro -z sas-opendistro
#sas-model-publish-kaniko
oc -n $project adm policy add-scc-to-user anyuid -z sas-model-publish-kaniko

#Deploy SFD
#Apply cluster-api resources to the cluster. As an administrator with cluster permissions, run
oc apply --selector="sas.com/admin=cluster-api" --server-side --force-conflicts -f $siteYaml
oc wait --for condition=established --timeout=120s -l "sas.com/admin=cluster-api" crd
#As an administrator with cluster permissions, run
oc apply --selector="sas.com/admin=cluster-wide" -f $siteYaml
#As an administrator with local cluster permissions, run
oc apply --selector="sas.com/admin=cluster-local" -f $siteYaml --prune
#As an administrator with namespace permissions, run
oc apply --selector="sas.com/admin=namespace" -f $siteYaml --prune 
#If you are performing an update, as an administrator with namespace permissions, run the following command to prune additional resources not in the default set.
#oc apply --selector="sas.com/admin=namespace" -f site.yaml --prune --prune-allowlist=autoscaling/v2/HorizontalPodAutoscaler
#wait for sas-readiness pod
echo "WAITING FOR sas-readiness POD TO REACH A READY STATE....."
oc wait --timeout=1m --for=condition=ready pod -l app=sas-readiness
#Tail logs to see the deployment progress
oc -n $project logs -f -l app=sas-readiness

