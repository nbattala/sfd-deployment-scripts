#!/usr/bin/env bash

# WARNING: THIS IS A PATCH SCRIPT THAT IS NOT INTENDED TO BE USED IN PRODUCTION ENVIRONMENTS. USE AT YOUR OWN RISK. THE RIGHT WAY TO RENEW LICENSE IS DESCRIBED IN THE DOCUMENTATION https://go.documentation.sas.com/doc/en/sasadmincdc/v_061/callicense/n14rkqa3cycmd0n1ub50k47x7lbb.htm#p0rlek5vmpshtwn16sxxxzmzu8n3

config-license-renew () {
    local licenseFilePath=$1
    # Add your code here to process the file
    # For example, you can read the contents of the file using 'cat' command
    if [ -f "$licenseFilePath" ]; then
        echo "File exists"
        # get current secret name
        currentSecretName=$(oc get secret -o jsonpath='{.items[?(@.type=="sas.com/license")].metadata.name}')
        if [ -n "$currentSecretName" ]; then
            echo "currentSecretName is $currentSecretName"
        # Patch the secret with the content from the file
        oc patch secret "$currentSecretName" --type=merge --patch "{\"data\":{\"SAS_LICENSE\":\"$(cat "$licenseFilePath" | base64 -w 0)\"}}"
        echo "License updated!"
        else
            echo "Error: currentSecretName is empty. Secret with type sas.com/license not found"
        fi
    else
        echo "ERROR: File $licenseFilePath does not exist"
    fi
}

# Call the function with the filename as an argument
#filename="/mnt/c/Users/nabatt/myWorkdir/downloads/downloads.2025.01/SASViyaV4_9D1XQ4_stable_2025.02_license_1740529526156.jwt"
#config-license-renew "$filename"