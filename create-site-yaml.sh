#!/usr/bin/env bash
export MSYS_NO_PATHCONV=1
set -o allexport
source properties.env
set +o allexport
export PATH=$PATH:./resources/tools

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
        if [[ -z "${!var}" ]]; then 
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

check_var project cadence imagePullSecret imageRegistry scrImageName rwxStorageClass \
    rwoStorageClass enableHA adHost adPort adUserDN adUserObjectFilter adGroupBaseDN adUserBaseDN redisHost redisPort \
    redisTlsEnabled redisServerDomain redisUser redisPassword redisProfileCompress kafkaHost kafkaPort kafkaBypass \
    kafkaConsumerEnabled kafkaConsumerTopic kafkaTdrTopic kafkaSecurityProtocol \
    customerCaCertsDir ingressHost tlsMode

if ${clusterPreReqCheck}; then
    k8s_resource_exists namespace "$project"
    k8s_resource_exists storageclass "$rwxStorageClass"
    k8s_resource_exists storageclass "$rwoStorageClass"
    k8s_resource_exists secret "$imagePullSecret"
fi

#extract tools
file_exists resources/tools.tar.gz
tar xzf resources/tools.tar.gz -C resources
chmod +x resources/tools/*

create_site_yaml () {
    dir_exists downloads
    rm -rf deploy
    mkdir -p deploy/site-config
    if [ ! -f "downloads/*$cadence*multipleAssets*.zip" ]; then
        unzip -o downloads/*$cadence*multipleAssets*.zip -d downloads
        tar xzf downloads/*$cadence*deploymentAssets*.tgz -C deploy
        cp downloads/*$cadence*license*.jwt deploy
        export licenseFile=$(ls downloads/*$cadence*license*.jwt | xargs -n 1 basename)
    else
        echo "multipleAssets*.zip file does not exist in downloads directory for cadence $cadence"
        exit 1
    fi
    dir_exists deploy/sas-bases
    chmod -Rf 755 deploy/sas-bases

    #kustomize
    file_exists resources/kustomization.yaml
    envsubst < resources/kustomization.yaml > deploy/kustomization.yaml

    #rwx-storage-class
    file_exists resources/rwx-storageclass.yaml
    envsubst < resources/rwx-storageclass.yaml > deploy/site-config/rwx-storageclass.yaml 

    #kaniko configuration
    mkdir -p deploy/site-config
    dir_exists deploy/sas-bases/examples/sas-model-publish/kaniko
    cp -a deploy/sas-bases/examples/sas-model-publish/kaniko deploy/site-config/
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
    if [[ ${redisTlsEnabled} ]]; then 
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
    if [[ -n ${kafkaClientCertificate} && -n ${kafkaClientPrivateKey} && -n ${kafkaTrustStore} ]]; then
        file_exists ${customerCaCertsDir}/${kafkaClientCertificate}
        export kafkaCertLocation=/customer-provided-ca-certificates/${kafkaClientCertificate}
        file_exists ${customerCaCertsDir}/${kafkaTrustStore}
        export kafkaTrustStoreLocation=/customer-provided-ca-certificates/${kafkaTrustStore}
        file_exists deploy/site-config/sas-detection/overlays/kustomization.yaml 
        file_exists ${customerCaCertsDir}/${kafkaClientPrivateKey}
        cp ${customerCaCertsDir}/${kafkaClientPrivateKey} deploy/site-config/sas-detection/overlays/kafkaClientPrivateKey.key
        yq e -i '.secretGenerator[].files += ["kafkaClientPrivateKey.key"]' deploy/site-config/sas-detection/overlays/kustomization.yaml
        export kafkaKeyLocation=/etc/kafka-client-mtls-key/kafkaClientPrivateKey.key
    else
        echo "kafkaClientCertificate or kafkaClientPrivateKey or kafkaTrustStore property is not set, skipping mTLS setup"
    fi
    envsubst < resources/sas-detection/overlays/kafka-config.yaml > deploy/site-config/sas-detection/overlays/kafka-config.yaml
    file_exists resources/sas-detection/overlays/kafka-secret.yaml
    envsubst < resources/sas-detection/overlays/kafka-secret.yaml > deploy/site-config/sas-detection/overlays/kafka-secret.yaml 

    #configure Active Directory, SSO, Redis for Designtime
    file_exists resources/sitedefault.yaml
    envsubst < resources/sitedefault.yaml >  deploy/site-config/sitedefault.yaml

    #add FSGROUP Value 
    unset MSYS_NO_PATHCONV
    nsGroupId=$(exec 2>/dev/null oc describe ns $project | grep sa.scc.supplemental-groups | awk '{print $2}' | awk -F '/' '{print $1}')
    export MSYS_NO_PATHCONV=1
    #check_var nsGroupId
    #echo $nsGroupId
    if [[ -z "${nsGroupId}" ]]; then 
        echo "Namespace Supplemental group number cannot be found. Skipping fsgroup update..."
    else
        mkdir -p deploy/site-config/security/container-security
        if [ $cadence = '2024.08' ]; then
            file_exists deploy/sas-bases/examples/security/container-security/update-fsgroup.yaml
            cp -a deploy/sas-bases/examples/security/container-security/update-fsgroup.yaml deploy/site-config/security/container-security
            sed -i "s/{{ FSGROUP_VALUE }}/${nsGroupId}/g" deploy/site-config/security/container-security/update-fsgroup.yaml
            yq e -i '.transformers += ["site-config/security/container-security/update-fsgroup.yaml"]' deploy/kustomization.yaml
        else   
            file_exists deploy/sas-bases/examples/security/container-security/configmap-inputs.yaml
            cp -a deploy/sas-bases/examples/security/container-security/configmap-inputs.yaml deploy/site-config/security/container-security
            sed -i "s/{{ FSGROUP_VALUE }}/${nsGroupId}/g" deploy/site-config/security/container-security/configmap-inputs.yaml
            yq e -i '.resources += ["site-config/security/container-security/configmap-inputs.yaml"]' deploy/kustomization.yaml
            yq e -i '.transformers += ["sas-bases/overlays/security/container-security/update-fsgroup.yaml"]' deploy/kustomization.yaml
        fi
    fi

    #mirror repository
    file_exists deploy/sas-bases/examples/mirror/mirror.yaml 
    cp -a deploy/sas-bases/examples/mirror/mirror.yaml deploy/site-config
    imageRegistryEsc="$(echo $imageRegistry | sed -e 's/\//\\&/g')"
    imageRegHost="$(echo "$imageRegistry" | cut -d '/' -f1)"
    sed -i "s/{{ MIRROR-HOST }}\/viya-4-x64_oci_linux_2-docker/${imageRegistryEsc}/g" deploy/site-config/mirror.yaml
    sed -i "s/{{ MIRROR-HOST }}/${imageRegistryHost}/g" deploy/site-config/mirror.yaml
    file_exists deploy/sas-bases/base/components/configmaps.yaml
    sed -i "s/viya-4-x64_oci_linux_2-docker\///g" deploy/sas-bases/base/components/configmaps.yaml

    #customer provided ca certificates
    dir_exists $customerCaCertsDir
    file_exists deploy/sas-bases/examples/security/customer-provided-ca-certificates.yaml 
    mkdir -p deploy/site-config/security/cacerts
    cp -a deploy/sas-bases/examples/security/customer-provided-ca-certificates.yaml deploy/site-config/security
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

    #enable HA if needed
    ${enableHA} && yq e -i '.transformers += ["sas-bases/overlays/scaling/ha/enable-ha-transformer.yaml"]' deploy/kustomization.yaml

    #enable TLS if needed
    case $tlsMode in
        front-door)
            ;;
        full-stack)
            export scheme=https
            sed -i "s/{{scheme}}/$scheme/g" deploy/kustomization.yaml
            yq e -i '.components += ["sas-bases/components/security/core/base/full-stack-tls"]' deploy/kustomization.yaml
            yq e -i '.components += ["sas-bases/components/security/network/route.openshift.io/route/full-stack-tls"]' deploy/kustomization.yaml
            yq e -i '.resources += ["sas-bases/overlays/cert-manager-issuer"]' deploy/kustomization.yaml
            file_exists deploy/sas-bases/examples/security/customer-provided-merge-sas-certframe-configmap.yaml 
            cp -a deploy/sas-bases/examples/security/customer-provided-merge-sas-certframe-configmap.yaml deploy/site-config/security/
            yq e -i '.literals.[0] = "SAS_CERTIFICATE_GENERATOR=cert-manager"' deploy/site-config/security/customer-provided-merge-sas-certframe-configmap.yaml
            yq e -i '.literals.[1] = "SAS_CERTIFICATE_DURATION=\"730\""' deploy/site-config/security/customer-provided-merge-sas-certframe-configmap.yaml
            yq e -i '.literals.[2] = "SAS_CERTIFICATE_ADDITIONAL_SAN_DNS="' deploy/site-config/security/customer-provided-merge-sas-certframe-configmap.yaml
            yq e -i '.literals.[3] = "SAS_CERTIFICATE_ADDITIONAL_SAN_IP="' deploy/site-config/security/customer-provided-merge-sas-certframe-configmap.yaml
            yq e -i '.literals.[4] = "EXCLUDE_MOZILLA_CERTS=false"' deploy/site-config/security/customer-provided-merge-sas-certframe-configmap.yaml
            #if [[ ! -z ${viyaCaIssuer} ]]; then
            #eval $(echo "yq e -i '.literals += \"SAS_CERTIFICATE_ISSUER=$viyaCaIssuer\"' deploy/site-config/security/customer-provided-merge-sas-certframe-configmap.yaml")
            #fi
            #since sas-ingress-certificate will have ca.crt, we are going to use it as CA certificate secret instead of actual CA secret that has CA private key which could be confidential and restricted at customer sites.
            #eval $(echo "yq e -i '.literals += \"SAS_CA_CERTIFICATE_SECRET_NAME=sas-ingress-certificate\"' deploy/site-config/security/customer-provided-merge-sas-certframe-configmap.yaml")
            #dir_exists deploy/sas-bases/components/security/network/route.openshift.io/route/full-stack-tls 
            #cp -a deploy/sas-bases/components/security/network/route.openshift.io/route/full-stack-tls deploy/site-config/security/full-stack-tls
            #find deploy/site-config/security/full-stack-tls -type f -exec sed -i 's/sas-viya-ca-certificate-secret/sas-ingress-certificate/g' {} +
            #yq e -i '.components += ["site-config/security/full-stack-tls"]' deploy/kustomization.yaml
            yq e -i '.generators += ["site-config/security/customer-provided-merge-sas-certframe-configmap.yaml"]' deploy/kustomization.yaml
            mkdir -p deploy/site-config/security/cacerts
            if [[ ! -z ${ingressCertificate} || ! -z ${ingressKey} || ! -z ${ingressCa} ]]; then
                file_exists deploy/sas-bases/examples/security/customer-provided-ingress-certificate.yaml
                cp -a deploy/sas-bases/examples/security/customer-provided-ingress-certificate.yaml deploy/site-config/security/customer-provided-ingress-certificate.yaml
                file_exists ${customerCaCertsDir}/${ingressCertificate}
                cp -a ${customerCaCertsDir}/${ingressCertificate} deploy/site-config/security/cacerts/sas-ingress-certificate.pem
                yq e -i '.files.[0] = "tls.crt=site-config/security/cacerts/sas-ingress-certificate.pem"' deploy/site-config/security/customer-provided-ingress-certificate.yaml
                file_exists ${customerCaCertsDir}/${ingressKey}
                cp -a ${customerCaCertsDir}/${ingressKey} deploy/site-config/security/cacerts/sas-ingress-key.pem
                yq e -i '.files.[1] = "tls.key=site-config/security/cacerts/sas-ingress-key.pem"' deploy/site-config/security/customer-provided-ingress-certificate.yaml
                file_exists ${customerCaCertsDir}/${ingressCa}
                cp -a ${customerCaCertsDir}/${ingressCa} deploy/site-config/security/cacerts/sas-ingress-ca.pem
                yq e -i '.files.[2] = "ca.crt=site-config/security/cacerts/sas-ingress-ca.pem"' deploy/site-config/security/customer-provided-ingress-certificate.yaml
                yq e -i '.generators += ["site-config/security/customer-provided-ingress-certificate.yaml"]' deploy/kustomization.yaml
            elif [[ ! -z ${ingressCaIssuer} ]]; then
                file_exists deploy/sas-bases/overlays/cert-manager-provided-ingress-certificate/ingress-annotation-transformer.yaml
                yq e -i '.transformers += ["site-config/security/ingress-annotation-transformer.yaml"]' deploy/kustomization.yaml
                file_exists deploy/sas-bases/examples/security/cert-manager-pre-created-ingress-certificate.yaml
                cp -a deploy/sas-bases/examples/security/cert-manager-pre-created-ingress-certificate.yaml deploy/site-config/security/cert-manager-pre-created-ingress-certificate.yaml
                sed -i "s/{{ INGRESS_DNS_ALIAS }}/$ingressHost/g;s/- {{ ANOTHER_INGRESS_DNS_ALIAS }}//g;s/sas-viya-issuer/$ingressCaIssuer/g;s/17532h/17520h/g" deploy/site-config/security/cert-manager-pre-created-ingress-certificate.yaml
                yq e -i '.resources += ["site-config/security/cert-manager-pre-created-ingress-certificate.yaml"]' deploy/kustomization.yaml
            else
                echo "ERROR: ingressCertificate, ingressKey, ingressCa or ingressCaIssuer property is not set, Cannot skip ingress certificate setup when tlsMode is full-stack"
                exit 1
            fi

            ;;
        *)
            export scheme=http
            sed -i "s/{{scheme}}/$scheme/g" deploy/kustomization.yaml
            yq e -i '.components += ["sas-bases/components/security/core/base/truststores-only"]' deploy/kustomization.yaml
            ;;
    esac



    #delete old site.yaml or backup
    [ -f site-$cadence.yaml ] && mv -f site-$cadence.yaml site-$cadence-$(date +%Y-%m-%d.%H:%M:%S).yaml
    ./resources/tools/kustomize build ./deploy -o site-$cadence.yaml
}

#prepare install script 
prepare_install_script () {
    install_dir=sfd-install-scripts
    export siteYaml=site-$cadence.yaml
    rm -rf $install_dir
    mkdir -p $install_dir
    envsubst < resources/install-sfd.sh > $install_dir/install-sfd.sh
    dir_exists deploy/sas-bases
    cp -a deploy/sas-bases/examples/cas/configure/cas-server-scc-host-launch.yaml $install_dir
    cp -a deploy/sas-bases/overlays/sas-microanalytic-score/service-account/sas-microanalytic-score-scc.yaml $install_dir
    cp -a deploy/sas-bases/overlays/sas-model-repository/service-account/sas-model-repository-scc.yaml $install_dir
    cp -a resources/scc/sas-opendistro-scc-modified-for-sysctl-transformer.yaml $install_dir
    cp -a deploy/sas-bases/overlays/sas-detection-definition/service-account/sas-detection-definition-scc.yaml $install_dir
    sed "s/{{ NAMESPACE }}/$project/g;s/default/sas-detection/g" deploy/sas-bases/examples/sas-detection/roles-and-rolebinding.yaml > $install_dir/sas-detection-roles-and-rolebinding.yaml
    file_exists site-$cadence.yaml
    cp -a site-$cadence.yaml $install_dir
    echo "Install script and manifests are written to $install_dir directory"
}

create_site_yaml
prepare_install_script