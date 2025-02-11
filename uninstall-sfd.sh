#!/usr/bin/env bash
source properties.env
siteYaml=site-$cadence.yaml

#export MSYS_NO_PATHCONV=1

export PATH=$PATH:${PWD}/resources/tools

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

delete-pvcs () {
    oc -n $project get pvc --no-headers -o custom-columns=":metadata.name" | xargs -n 1 oc delete pvc
}

delete-project () {
    oc delete project $project
}

while true; do
    read -p "Do you wish to delete any PVCs used by SFD as well? " yn
    case $yn in
        [Yy]* ) delete-pvcs ; break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done

while true; do
    read -p "Do you wish to delete the project $project used by SFD as well? " yn
    case $yn in
        [Yy]* ) delete-project ; break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done

