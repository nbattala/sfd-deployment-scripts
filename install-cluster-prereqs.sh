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
  skuName: Premium_LRS
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
echo "Enter Image Registry Host ($imageRegHost) Username:"
read imageRegUser
echo "Enter Image Registry Host ($imageRegHost) Password:"
read -s imageRegPwd
oc create secret docker-registry $imagePullSecret \
	--docker-server $imageRegHost \
	--docker-username $imageRegUser \
	--docker-password $imageRegPwd

#create ingress ca cluster issuer
oc -n cert-manager create secret tls myca-ingress-secret --cert=../MyCA/myca.crt --key=../MyCA/myca-unencrypted.key
cat <<EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: myca-ingress-issuer
spec:
  ca:
    secretName: myca-ingress-secret
EOF

#create pod ca issuer
cat << EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: myca-pod-selfsigning-issuer
spec:
  selfSigned: {}
EOF
cat << EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myca-pod-ca-certificate
spec:
  secretName: myca-pod-certificate-secret
  commonName: "myca-pod-ca-certificate"
  duration: 43800h # 5 years
  renewBefore: 1h # 1 hour
  isCA: true
  issuerRef:
    name: myca-pod-selfsigning-issuer
    kind: Issuer
EOF
cat << EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: myca-pod-issuer
spec:
  ca:
    secretName: myca-pod-certificate-secret
EOF
#create a secret with just the CA to be used for the pods truststore- This does not work as pods expect both tls.crt and tls.key.
#oc get secret myca-pod-certificate-secret -o=jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/myca-pod-ca-secret.pem
#oc create secret generic myca-pod-ca-secret --from-file=tls.crt=/tmp/myca-pod-ca-secret.pem