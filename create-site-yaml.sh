#!/usr/bin/env bash
set -o allexport
source properties.env
set +o allexport

k8s_resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    if [[ ! $(oc get "$resource_type" "$resource_name") ]]; then
	    echo "ERROR: "$resource_type" "${resource_name}" not found!"
	    exit 1;
    fi
}

file_exists() {
    local file_path="$1"
    if [ ! -f "$file_path" ]; then
        echo "ERROR: The file $file_path does not exist."
        exit 1;
    fi
}

dir_exists() {
    local dir_path="$1"
    if [ ! -d "$dir_path" ]; then
	    echo "ERROR: The directory $dir_path does not exist."
	    exit 1;
    fi
}

check_var() {
    for var in "$@"
    do 
        echo $"${var}"
        if [ -z ${!var+x} ]; then 
            echo "ERROR: Variable $var is unset or empty in properties.env"
            exit 1; 
        fi
    done
}



if [ -z "${ingressHost}" ]; then
    APPS_DOMAIN=$(oc get ingresscontroller.operator.openshift.io -n openshift-ingress-operator -o jsonpath='{.items[].status.domain}')
    export ingressHost="${project}.${APPS_DOMAIN}"
    echo "Ingress Host is : $ingressHost"
fi

tstvar=
check_var project siteYaml cadence imagePullSecret imageRegistry scrImageName rwxStorageClass \
    rwoStorageClass enableHA adHost adPort adUserDN adUserObjectFilter adGroupBaseDN adUserBaseDN redisHost redisPort \
    redisTlsEnabled redisServerDomain redisUser redisPassword redisProfileCompress kafkaHost kafkaPort kafkaBypass \
    kafkaConsumerEnabled kafkaConsumerTopic kafkaTdrTopic kafkaSecurityProtocol kafkaSaslUsername \
    kafkaSaslPassword customerCaCertsDir ingressHost tstvar

if ${clusterPreReqCheck}; then
    k8s_resource_exists namespace "$project"
    k8s_resource_exists storageclass "$rwxStorageClass"
    k8s_resource_exists storageclass "$rwoStorageClass"
    k8s_resource_exists secret "$imagePullSecret"
fi

dir_exists downloads
rm -rf downloads/sas-bases
if [ ! -f "downloads/*$cadence*multipleAssets*.zip" ]; then
    unzip -o downloads/*$cadence*multipleAssets*.zip -d downloads
    tar xzf downloads/*$cadence*deploymentAssets*.tgz -C downloads
else
    echo "multipleAssets*.zip file does not exist in downloads directory for cadence $cadence"
    exit 1
fi
dir_exists downloads/sas-bases
chmod -Rf 755 deploy/sas-bases
rm -rf deploy
mkdir -p deploy/site-config
cp -a downloads/sas-bases deploy

#extract tools
file_exists resources/tools.tar.gz
tar xzf resources/tools.tar.gz -C resources
chmod +x resources/tools/*

#rwx-storage-class
cat > deploy/site-config/rwx-storageclass.yaml <<EOF
kind: RWXStorageClass
metadata:
 name: wildcard
spec:
 storageClassName: ${rwxStorageClass}
EOF

#kaniko configuration
mkdir -p deploy/site-config
dir_exists downloads/sas-bases/examples/sas-model-publish/kaniko
cp -a downloads/sas-bases/examples/sas-model-publish/kaniko deploy/site-config/
rm -f deploy/site-config/kaniko/README.md
chmod -R u+rw deploy/site-config
file_exists deploy/site-config/kaniko/storage.yaml
sed -i "s/{{ STORAGE-CAPACITY }}/50Gi/g" deploy/site-config/kaniko/storage.yaml
sed -i "s/{{ STORAGE-CLASS-NAME }}/${rwxStorageClass}/g" deploy/site-config/kaniko/storage.yaml

#configure rwo storage class (for customers who do not have rwo sc set as default or do not want default sc to be used)
dir_exists resources/rwoStorageClass
cp -a resources/rwoStorageClass deploy/site-config
file_exists deploy/site-config/rwoStorageClass/crunchy-storage-transformer.yaml
sed -i "s/{{ POSTGRES-STORAGE-CLASS }}/${rwoStorageClass}/g" deploy/site-config/rwoStorageClass/crunchy-storage-transformer.yaml
sed -i "s/{{ BACKREST-STORAGE-CLASS }}/${rwoStorageClass}/g" deploy/site-config/rwoStorageClass/crunchy-storage-transformer.yaml
file_exists deploy/site-config/rwoStorageClass/opendistro-storage-transformer.yaml
sed -i "s/{{ STORAGE-CLASS }}/${rwoStorageClass}/g" deploy/site-config/rwoStorageClass/opendistro-storage-transformer.yaml
file_exists deploy/site-config/rwoStorageClass/redis-modify-storage.yaml
sed -i "s/{{ STORAGE-CLASS }}/${rwoStorageClass}/g" deploy/site-config/rwoStorageClass/redis-modify-storage.yaml
file_exists deploy/site-config/rwoStorageClass/consul-storage-transformer.yaml
sed -i "s/{{ STORAGE-CLASS }}/${rwoStorageClass}/g" deploy/site-config/rwoStorageClass/consul-storage-transformer.yaml
file_exists deploy/site-config/rwoStorageClass/rabbitmq-storage-transformer.yaml
sed -i "s/{{ STORAGE-CLASS }}/${rwoStorageClass}/g" deploy/site-config/rwoStorageClass/rabbitmq-storage-transformer.yaml


#configure ip bind for sas-consul-server
file_exists resources/sas-consul-server-ip-bind-transformer.yaml
cp -a resources/sas-consul-server-ip-bind-transformer.yaml deploy/site-config

#configure SCR sidecar for sas-detection
file_exists resources/sas-detection/overlays/kustomization.yaml
cp -a resources/sas-detection deploy/site-config
file_exists resources/sas-detection/overlays/redis-config.yaml
if [[ ${redisTlsEnabled} ]] 
then 
    export redisTlsScr='T' 
else   
    export redisTlsScr='F'
fi
envsubst < resources/sas-detection/overlays/redis-config.yaml > deploy/site-config/sas-detection/overlays/redis-config.yaml
export scrRegistryUrl=${imageRegistry}/${scrImageName}
file_exists resources/sas-detection/overlays/sas-detection-patch.yaml
envsubst < resources/sas-detection/overlays/sas-detection-patch.yaml > deploy/site-config/sas-detection/overlays/sas-detection-patch.yaml
file_exists resources/sas-detection/overlays/redis-secret.yaml
envsubst <  resources/sas-detection/overlays/redis-secret.yaml > deploy/site-config/sas-detection/overlays/redis-secret.yaml
file_exists resources/sas-detection/overlays/kafka-config.yaml
envsubst < resources/sas-detection/overlays/kafka-config.yaml > deploy/site-config/sas-detection/overlays/kafka-config.yaml
file_exists resources/sas-detection/overlays/kafka-secret.yaml
envsubst < resources/sas-detection/overlays/kafka-secret.yaml > deploy/site-config/sas-detection/overlays/kafka-secret.yaml 

#configure Active Directory, SSO, Redis for Designtime
file_exists resources/sitedefault.yaml
envsubst < resources/sitedefault.yaml >  deploy/site-config/sitedefault.yaml

#add FSGROUP Value
nsGroupId=$(oc describe ns $project | grep sa.scc.supplemental-groups | awk '{print $2}' | awk -F '/' '{print $1}')
check_var $nsGroupId
mkdir -p deploy/site-config/security/container-security

file_exists downloads/sas-bases/examples/security/container-security/configmap-inputs.yaml
cp -a downloads/sas-bases/examples/security/container-security/configmap-inputs.yaml deploy/site-config/security/container-security
sed -i "s/{{ FSGROUP_VALUE }}/${nsGroupId}/g" deploy/site-config/security/container-security/configmap-inputs.yaml

#mirror repository
file_exists downloads/sas-bases/examples/mirror/mirror.yaml 
cp -a downloads/sas-bases/examples/mirror/mirror.yaml deploy/site-config
imageRegistryEsc="$(echo $imageRegistry | sed -e 's/\//\\&/g')"
imageRegHost="$(echo "$imageRegistry" | cut -d '/' -f1)"
sed -i "s/{{ MIRROR-HOST }}\/viya-4-x64_oci_linux_2-docker/${imageRegistryEsc}/g" deploy/site-config/mirror.yaml
sed -i "s/{{ MIRROR-HOST }}/${imageRegistryHost}/g" deploy/site-config/mirror.yaml
file_exists deploy/sas-bases/base/components/configmaps.yaml
sed -i "s/viya-4-x64_oci_linux_2-docker\///g" deploy/sas-bases/base/components/configmaps.yaml

#customer provided ca certificates
dir_exists $customerCaCertsDir
file_exists downloads/sas-bases/examples/security/customer-provided-ca-certificates.yaml 
mkdir -p deploy/site-config/security/cacerts
cp -a downloads/sas-bases/examples/security/customer-provided-ca-certificates.yaml deploy/site-config/security
chmod +w deploy/site-config/security/customer-provided-ca-certificates.yaml
sed -i '/- {{ CA_CERTIFICATE_FILE_NAME }}/d' deploy/site-config/security/customer-provided-ca-certificates.yaml
for file in "$customerCaCertsDir"/*.pem
do
    if [ -f "$file" ]; then 
        if [[ $file = *" "* ]]; then 
            # Remove spaces and replace with underscores
            new_file=$(echo "$file" | tr ' ' '_')
            # Rename the file
            mv "$file" "$new_file"
        fi    
    fi
done

for file in "$customerCaCertsDir"/*.pem
do
    if [ -f "$file" ]; then 
        if [[ ! $(openssl x509 -in ${file} -text -noout) ]]; then
            echo "ERROR: CA cert file $file is not in pem format"
            exit 1;
        else
            cp -a "$file" deploy/site-config/security/cacerts
            echo "- site-config/security/cacerts/$(basename $file)" >> deploy/site-config/security/customer-provided-ca-certificates.yaml
        fi
    fi
done

#image pull secret
file_exists resources/image-pull-secret/sas-image-pull-secret-patch.yaml
mkdir -p deploy/site-config/image-pull-secret
envsubst < resources/image-pull-secret/sas-image-pull-secret-patch.yaml > deploy/site-config/image-pull-secret/sas-image-pull-secret-patch.yaml

#kustomize
file_exists resources/kustomization.yaml
envsubst < resources/kustomization.yaml > deploy/kustomization.yaml
#ln -s ../downloads/sas-bases deploy/
${enableHA} && ./resource/tools/yq e -i '.transformers += ["sas-bases/overlays/scaling/ha/enable-ha-transformer.yaml"]' deploy/kustomization.yaml
rm -f site.yaml
./resources/tools/kustomize build ./deploy -o site.yaml
