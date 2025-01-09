#!/usr/bin/env bash

set -o allexport
source properties.env
set +o allexport

oc new-project $project --display-name 'SAS FD Design Time namespace - Viya4'
#oc new-project $operatorProject --display-name 'SAS FD Viya4 Deployment Operator'

#create rwx storage class with NFS options
cat <<EOF | oc apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${rwxStorageClass}
mountOptions:
  - nconnect=4
parameters:
  skuName: Standard_LRS
  protocol: nfs
provisioner: file.csi.azure.com
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF

#create rwo storage class 
cat <<EOF | oc apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
  name: ${rwoStorageClass}
parameters:
  skuname: Premium_LRS
provisioner: disk.csi.azure.com
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF

#create imagepullsecret
imageRegHost="$(echo "$imageRegistry" | cut -d '/' -f1)"
echo "Enter Image Registry Host Username:"
read imageRegUser
echo "Enter Image Registry Host Password:"
read -s imageRegPwd
oc create secret docker-registry $imagePullSecret \
	--docker-server $imageRegHost \
	--docker-username $imageRegUser \
	--docker-password $imageRegPwd

