#!/usr/bin/env bash
source env.properties

#Remove Service Account links and SCCs
for oc_scc in $(oc get clusterrolebinding | grep "system:openshift:scc:" | awk '{ print $1 }'); do
    crb_name=$(oc get clusterrolebinding $oc_scc -o json | jq -r '.roleRef.name')
    sa_names=$(oc get clusterrolebinding $oc_scc -o json | jq -r '.subjects[] | select(.namespace == '\"$project\"') | .name')
    for sa_name in $sa_names; do
        if [[ ! -z $sa_name ]]; then
            echo "oc -n $project adm policy remove-scc-from-user ${crb_name##*:} -z $sa_name"
        fi 
    done
done
for sas_scc in $(oc get scc | grep sas | awk '{ print$1 }'); do oc delete scc $sas_scc; done
for sas_scc in $(oc get scc | grep pgo | awk '{ print$1 }'); do oc delete scc $sas_scc; done

oc -n $project delete postgresclusters --selector="sas.com/deployment=sas-viya"

oc delete -f $siteYaml
