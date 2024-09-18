#!/usr/bin/env bash

config-sfd-rules-studio() {
    printf "Entering ${FUNCNAME[0]}\n"
    curl -k --request PUT --url ${INGRESS_URL}/identities/groups/SDARulesEditor/userMembers/${sfdAdminUserId} --header 'Content-Type: application/json' --header "Authorization: Bearer $ACCESS_TOKEN"
    curl -k --request PUT --url ${INGRESS_URL}/identities/groups/SDASrRulesEditor/userMembers/${sfdAdminUserId} --header 'Content-Type: application/json' --header "Authorization: Bearer $ACCESS_TOKEN"
    curl -k --request PUT --url ${INGRESS_URL}/identities/groups/SDASystemAdmin/userMembers/${sfdAdminUserId} --header 'Content-Type: application/json' --header "Authorization: Bearer $ACCESS_TOKEN"

    USER_ACCESS_TOKEN=$(curl -k -X POST ${INGRESS_URL}/SASLogon/oauth/token -H 'Accept: application/json' -H 'Content-type: application/x-www-form-urlencoded' -H 'Authorization: Basic c2FzLmVjOg==' -d "grant_type=password&username=${sfdAdminUserId}&password=${sfdAdminUserPwd}"|jq -r '.access_token')
    #create Message Classifications
    printf "Create Message Classifications\n"
    curl -k --request POST \
        --url ${INGRESS_URL}/detectionDefinition/messageClassifications/imports \
        --header 'Content-Type: text/csv' \
        --header "Authorization: Bearer $USER_ACCESS_TOKEN" \
        -d 'name,displayName,keyCode
GLOBAL,GLOBAL,1
DEBIT,DEBIT,1.1
CREDIT,CREDIT,1.2'

    printf "Obtain Message Classification Ids\n"
    export globalMCId=$(curl -k -X GET ${INGRESS_URL}/detectionDefinition/messageClassifications -H "Authorization: Bearer $USER_ACCESS_TOKEN" -H "Content-Type: application/vnd.sas.collection+json" | jq -r '.items[] | select(.name == "GLOBAL") | .id')
    printf "globalMcId= %s\n" "$globalMCId"

    #create Custom Message Schema from template
    FILE=custom-message-schema-template.yaml
    if [ ! -f "$FILE" ]; then
        echo "ERROR: $FILE does not exist."
        exit 1
    else
        cat "$FILE" | base64 -w 0 > ."$FILE".b64 
        curl -k --request POST \
        --url ${INGRESS_URL}/detectionMessageSchema/templates?autoapply=true \
        --header "Authorization: Bearer ${USER_ACCESS_TOKEN}" \
        --header 'Accept: application/vnd.sas.detection.message.schema.template.summary+json, application/json, application/vnd.sas+json' \
        --header 'Content-Encoding: base64'  \
        --header 'Content-Type: application/vnd.sas.detection.message.schema.template+yaml' \
        --data @."$FILE".b64
    fi
    #create organizations
    printf "Create Organization\n"
    printf "%s" \
    { \
    \"displayName\"             : \"BOFA\", \
    \"name\"                    : \"BOFA\", \
    \"description\"             : \"'BOFA Organization'\", \
    \"messageClassificationId\" : \"${globalMCId}\", \
        \"schemaRelations\": [ \
            { \
                \"schemaName\": \"'CustomDebitAuthorizations'\" \
            } \
        ], \
        \"roleRelations\": [ \
            { \
                \"roleId\": \"SDASystemAdmin\" \
            } \
        ] \
    } \
    |jq| tee /tmp/.bofaOrganization.json > /dev/null

    curl -k -X POST ${INGRESS_URL}/detectionDefinition/organizations \
     -H "Authorization: Bearer $USER_ACCESS_TOKEN" \
     -H "Content-Type: application/vnd.sas.detection.organization+json" \
     -d @/tmp/.bofaOrganization.json

    #Obtain Organization ID
    export bofaOrg=$(curl -k -X GET ${INGRESS_URL}/detectionDefinition/organizations \
        -H "Authorization: Bearer $USER_ACCESS_TOKEN" \
        -H "Content-Type: application/vnd.sas.collection+json" 2>/dev/null \
        | jq -r '.items[] | select(.name == "BOFA") | .id')
    echo "BofA Organization Id: ${bofaOrg}"

    ### SECTION ############################################
    echo "Associate Role to Organization"
    ########################################################
    curl -k -X POST ${INGRESS_URL}/detectionDefinition/organizations/${bofaOrg}/roleRelationships/SDARulesEditor \
     -H "Authorization: Bearer $USER_ACCESS_TOKEN" \
     -H "Content-Type: application/vnd.sas.detection.organization+json"

    curl -k -X POST ${INGRESS_URL}/detectionDefinition/organizations/${bofaOrg}/roleRelationships/SDASrRulesEditor \
     -H "Authorization: Bearer $USER_ACCESS_TOKEN" \
     -H "Content-Type: application/vnd.sas.detection.organization+json"
    ### SECTION ############################################
    echo "Attach Published Destination to Organizations"
    ########################################################
    echo "Updating Publish destination for organization=${bofaOrg}"
    curl -k --location --request PATCH ${INGRESS_URL}/detectionDefinition/deploymentDefinitions?organization=${bofaOrg} \
        -H 'Accept: application/vnd.sas.detection.deployment.definition+json, application/json, application/vnd.sas.error+json' \
        -H "Authorization: Bearer $USER_ACCESS_TOKEN" \
        -H "Content-Type: application/vnd.sas.detection.deployment.definition+json" \
        -H "If-Match: *" \
        --data '{
        "destination": "SDADockerRegistry"
        }'

}