#!/usr/bin/env bash
oc patch deployment sas-detection --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/ports/0/containerPort", "value": 8777}]'
oc patch deployment sas-detection --patch-file sas-detection-patch.yaml
oc patch deployment sas-detection --patch-file scr-sidecar-patch.yaml
#scr - create cm and secrets for scr-redis-secrets, scr-redis-config, scr-redis-certs
#sas-detection - create cm and secrets for Kafka and redis credentials
echo "Please enter Kafka SASL Username:"
read -r kafkaUser
echo "Please enter Kafka SASL Password:"
read -rs kafkaPwd
oc create secret generic sas-detection-kafka-secret --from-literal=SAS_DETECTION_KAFKA_SASL_USERNAME="${kafkaUser}" --from-literal=SAS_DETECTION_KAFKA_SASL_PASSWORD="${kafkaPwd}"

file_exists() {
    local file_path="$1"
    if [ ! -f "$file_path" ]; then
        echo "ERROR: The file $file_path does not exist."
        exit 1
    fi
}

file_exists "sas-detection-kafka-config.env"
oc create cm sas-detection-kafka-config --from-env-file=sas-detection-kafka-config.env 

echo "Please enter the path to Kafka TLS Root CA in pem format:"
read -r kafkaTrustStore
file_exists "$kafkaTrustStore"
oc create cm bank-ca-chain --from-file ca.crt="$kafkaTrustStore"


