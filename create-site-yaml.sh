#!/usr/bin/env bash

source env.properties

APPS_DOMAIN=$(oc get ingresscontroller.operator.openshift.io -n openshift-ingress-operator -o jsonpath='{.items[].status.domain}')
ingressHost="${project}.${APPS_DOMAIN}"

k8s_resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    if [ ! $(oc get "$resource_type" "$resource_name") ]; then
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
        if [ -z ${!var+x} ]; then 
            echo "ERROR: $var is unset"
            exit 1; 
        fi
    done
}

check_var project siteYaml imagePullSecret imageRepository scrImageName rwxStorageClass \
    rwoStorageClass adHost adPort adUserDN adGroupBaseDN adUserBaseDN redisHost redisPort \
    redisTlsEnabled redisServerDomain redisUser redisPassword kafkaHost kafkaPort kafkaBypass \
    kafkaConsumerEnabled kafkaConsumerTopic kafkaTdrTopic kafkaSecurityProtocol kafkaSaslUsername \
    kafkaSaslPassword

k8s_resource_exists namespace "$project"
k8s_resource_exists storageclass "$rwxStorageClass"
k8s_resource_exists storageclass "$rwoStorageClass"
dir_exists downloads/sas-bases
rm -rf deploy/site-config
mkdir -p deploy/site-config

#rwx-storage-class
cat > deploy/site-config/rwx-storageclass.yaml <<EOF
kind: RWXStorageClass
metadata:
 name: wildcard
spec:
 storageClassName: ${rwxStorageClass}
EOF

#sas-shared-config
#change the Service URL to https and port 443 for TLS.. Changed to Test noTLS for BofA.
cat > deploy/site-config/sas-shared-config.yaml <<EOF
apiVersion: builtin
kind: ConfigMapGenerator
metadata:
  name: sas-shared-config
behavior: merge
literals:
  - SAS_SERVICES_URL=http://${ingressHost}:80
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
file_exists downloads/sas-bases/examples/crunchydata/storage/crunchy-storage-transformer.yaml
cp -a downloads/sas-bases/examples/crunchydata/storage/crunchy-storage-transformer.yaml deploy/site-config/rwoStorageClass
sed -i "s/{{ POSTGRES-STORAGE-CLASS }}/${rwoStorageClass}/g" deploy/site-config/rwoStorageClass/crunchy-storage-transformer.yaml
sed -i "s/{{ BACKREST-STORAGE-CLASS }}/${rwoStorageClass}/g" deploy/site-config/rwoStorageClass/crunchy-storage-transformer.yaml
file_exists deploy/site-config/rwoStorageClass/opendistro-storage-transformer.yaml
sed -i "s/{{ STORAGE-CLASS }}/${rwoStorageClass}/g" deploy/site-config/rwoStorageClass/opendistro-storage-transformer.yaml
file_exists downloads/sas-bases/examples/redis/operator/redis-modify-storage.yaml
cp -a downloads/sas-bases/examples/redis/operator/redis-modify-storage.yaml deploy/site-config/rwoStorageClass
sed -i "s/{{ STORAGE-CLASS }}/${rwoStorageClass}/g" deploy/site-config/rwoStorageClass/redis-modify-storage.yaml
file_exists deploy/site-config/rwoStorageClass/consul-storage-transformer.yaml
sed -i "s/{{ STORAGE-CLASS }}/${rwoStorageClass}/g" deploy/site-config/rwoStorageClass/consul-storage-transformer.yaml
file_exists deploy/site-config/rwoStorageClass/rabbitmq-storage-transformer.yaml
sed -i "s/{{ STORAGE-CLASS }}/${rwoStorageClass}/g" deploy/site-config/rwoStorageClass/rabbitmq-storage-transformer.yaml


#configure ip bind for sas-consul-server
file_exists resources/sas-consul-server-ip-bind-transformer.yaml
cp -a resources/sas-consul-server-ip-bind-transformer.yaml deploy/site-config

#configure SCR sidecar for sas-detection
dir_exists resources/sas-detection/overlays
cp -a resources/sas-detection deploy/site-config
file_exists deploy/site-config/sas-detection/overlays/redis-config.yaml
[ ${redisTlsEnabled} = 'true' ] && redisTlsScr='true' || redisTlsScr='false'
sed -i "s/{redis-host}/${redisHost}/g;s/{redis-port}/${redisPort}/g;s/{redis-server-domain}/${redisServerDomain}/g;s/{redis-tls-enabled}/${redisTlsEnabled}/g;s/{redis-tls-scr}/${redisTlsScr}/g" deploy/site-config/sas-detection/overlays/redis-config.yaml
file_exists deploy/site-config/sas-detection/overlays/redis-secret.yaml
sed -i "s/{redis-user}/${redisUser}/g;s/{redis-pwd}/${redisPassword}/g" deploy/site-config/sas-detection/overlays/redis-secret.yaml
file_exists deploy/site-config/sas-detection/overlays/kafka-config.yaml
sed -i "s/{kafka-host}/${kafkaHost}:${kafka-port}/g;s/{tdr-topic}/${kafkaTdrTopic}/g;s/{kafka-cons-enable}/${kafkaConsumerEnabled}/g;s/{kafka-host-verify}/${kafkaHostnameVerify}/g;s/{reject-topic}/${kafkaRejectTopic}/g;s/{kafka-sec-prot}/${kafkaSecurityProtocol}/g;s/{input-topic}/${kafkaConsumerTopic}/g;s/{kafka-bypass}/${kafkaBypass}/g" deploy/site-config/sas-detection/overlays/kafka-config.yaml
file_exists deploy/site-config/sas-detection/overlays/kafka-secret.yaml
sed -i "s/{kafka-sasl-user}/${kafkaSaslUsername}/g;s/{kafka-sasl-password}/${kafkaSaslPassword}/g" deploy/site-config/sas-detection/overlays/kafka-secret.yaml 

#configure Active Directory information
file_exists resources/sitedefault.yaml
cp -a resources/sitedefault.yaml deploy/site-config
sed -i "s/{ldap-host}/${adHost}/g;s/{ldap-password}/${adPasswd}/g;s/{ldap-port}/${adPort}/g;s/{ldap-user}/${adUserDN}/g;s/{ldap-group-dn}/${adGroupBaseDN}/g;s/{ldap-user-dn}/${adUserBaseDN}/g" deploy/site-config/sitedefault.yaml

#remove seccomp
nsGroupId=$(oc describe ns $project | grep sa.scc.supplemental-groups | awk '{print $2}' | awk -F '/' '{print $1}')
mkdir -p deploy/site-config/security/container-security
file_exists downloads/sas-bases/examples/security/container-security/update-fsgroup.yaml
cp -a downloads/sas-bases/examples/security/container-security/update-fsgroup.yaml deploy/site-config/security/container-security
sed -i "s/{{ FSGROUP_VALUE }}/${nsGroupId}/g" deploy/site-config/security/container-security/update-fsgroup.yaml

#mirror repository
file_exists downloads/sas-bases/examples/mirror/mirror.yaml 
cp -a downloads/sas-bases/examples/mirror/mirror.yaml deploy/site-config
sed -i "s/{{ MIRROR-HOST }}\/viya-4-x64_oci_linux_2-docker/${imageRegistry}/g" deploy/site-config/mirror.yaml

#customer provided ca certificates
dir_exists $customerCaCertsDir
file_exists downloads/sas-bases/examples/security/customer-provided-ca-certificates.yaml 
mkdir -p deploy/site-config/security/cacerts
cp -a downloads/sas-bases/examples/security/customer-provided-ca-certificates.yaml deploy/site-config/security
sed -i '/- {{ CA_CERTIFICATE_FILE_NAME }}/d' deploy/site-config/security/customer-provided-ca-certificates.yaml
for file in "$customerCaCertsDir"/*.pem
do
    if [ -f "$file" ]; then 
        # Remove spaces and replace with underscores
        new_file=$(echo "$file" | tr ' ' '_')
        # Rename the file
        mv "$file" "$new_file"
        if [ ! $(openssl x509 -in ${new_file} -text -noout > /dev/null) ]; then
            echo "ERROR: CA cert file $new_file is not in pem format"
            exit 1;
        else
            cp -a "$file" deploy/site-config/security/cacerts
            echo "- site-config/security/cacerts/$new_file" >> deploy/site-config/security/customer-provided-ca-certificates.yaml
        fi
    fi
done