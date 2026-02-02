#!/usr/bin/env bash

config-sfd-rules-studio() {
    
    printf "Entering ${FUNCNAME[0]}\n"
    #get passwod for $sfdAdminUserId
    echo "please enter password of ${sfdAdminUserId}":
    read -rs sfdAdminUserPwd

    curl -k --request PUT --url ${INGRESS_URL}/identities/groups/SDARulesEditor/userMembers/${sfdAdminUserId} --header 'Content-Type: application/json' --header "Authorization: Bearer $ACCESS_TOKEN"
    curl -k --request PUT --url ${INGRESS_URL}/identities/groups/SDASrRulesEditor/userMembers/${sfdAdminUserId} --header 'Content-Type: application/json' --header "Authorization: Bearer $ACCESS_TOKEN"
    curl -k --request PUT --url ${INGRESS_URL}/identities/groups/SDASystemAdmin/userMembers/${sfdAdminUserId} --header 'Content-Type: application/json' --header "Authorization: Bearer $ACCESS_TOKEN"

}
