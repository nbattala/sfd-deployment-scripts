#!/usr/bin/env bash

oc project $project

#Apply and bind SCCs
if [ -e cas-server-scc-host-launch.yaml ]; then
	oc apply -f cas-server-scc-host-launch.yaml
	oc -n $project adm policy add-scc-to-user sas-cas-server-host -z sas-cas-server
elif [ -e cas-server-scc.yaml ]; then
	oc apply -f cas-server-scc.yaml
	oc -n $project adm policy add-scc-to-user sas-cas-server -z sas-cas-server
else
	 echo "ERROR: cas-server scc file not found!"
	 exit 1
fi
oc apply -f sas-microanalytic-score-scc.yaml
oc -n $project adm policy add-scc-to-user sas-microanalytic-score -z sas-microanalytic-score
oc apply -f sas-detection-definition-scc.yaml
oc -n $project adm policy add-scc-to-user sas-detection-definition -z sas-detection-definition 
oc apply -f sas-model-repository-scc.yaml
oc -n $project adm policy add-scc-to-user sas-model-repository -z sas-model-repository
oc apply -f pyconfig-scc.yaml
oc -n $project adm policy add-scc-to-user sas-pyconfig -z sas-pyconfig
oc -n $project adm policy add-scc-to-user nonroot -z sas-programming-environment
#launcher host user false
oc -n $project adm policy add-scc-to-user 

if [ -e sas-opendistro-scc-modified-for-sysctl-transformer.yaml ]; then
	oc apply -f sas-opendistro-scc-modified-for-sysctl-transformer.yaml
elif [ -e sas-opendistro-scc-modified-for-run-user-transformer.yaml ]; then
	oc apply -f sas-opendistro-scc-modified-for-run-user-transformer.yaml
else
	echo "ERROR: sas-opendistro scc not found!"
	exit 1
fi
oc -n $project adm policy add-scc-to-user sas-opendistro -z sas-opendistro
#sas-model-publish
if [[ $modelPublishMode == "kaniko" ]]; then
	oc -n $project adm policy add-scc-to-user anyuid -z sas-model-publish-kaniko
else
	oc apply -f sas-model-publish-scc.yaml
	oc apply -f buildkit-scc.yaml
	oc -n $project adm policy add-scc-to-user sas-model-publish -z sas-model-publish-buildkit
	oc -n $project adm policy add-scc-to-user sas-model-publish -z default
	oc -n $project adm policy add-scc-to-user sas-buildkit -z sas-buildkit
fi
#sas-detection-role-bindings (metrics)
oc -n $project apply -f sas-detection-roles-and-rolebinding.yaml

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
#restart CAS pods as noted in deployment notes
oc -n $project delete pods -l app.kubernetes.io/managed-by=sas-cas-operator
#Tail logs to see the deployment progress
oc -n $project logs -f -l app=sas-readiness

