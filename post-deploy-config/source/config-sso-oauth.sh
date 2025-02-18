
config-sso-oauth() {
    echo "Entering ${FUNCNAME[0]}"
    #configure SSO OAUTH
    if [ "$1" == "disable" ]; then
     echo "Disabling SSO OAUTH"
     oauth_config_id=$(curl -k -X GET ${INGRESS_URL}/configuration/configurations \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H 'Accept: application/json, application/vnd.sas.collection+json;version=2' \
          -H 'Accept-Item: ' |  jq -r '.items[] | select(.metadata.mediaType == "application/vnd.sas.configuration.config.sas.logon.oauth.providers+json;version=1") | .id')
     if [ -z "$oauth_config_id" ]; then
          echo "SSO OAUTH configuration not found"
     else 
	  echo "Deleting sas.logon.oauth.provider ${oauth_config_id}"
          curl -k -X DELETE ${INGRESS_URL}/configuration/configurations/${oauth_config_id} \
          -H "Authorization: Bearer $ACCESS_TOKEN" 
     fi
     zone_config_id=$(curl -k -X GET ${INGRESS_URL}/configuration/configurations \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H 'Accept: application/json, application/vnd.sas.collection+json;version=2' \
          -H 'Accept-Item: ' |  jq -r '.items[] | select(.metadata.mediaType == "application/vnd.sas.configuration.config.sas.logon.zone+json;version=2") | .id')
     if [ -z "$zone_config_id" ]; then
          echo "SSO OAUTH zone configuration not found"
     else 
	  echo "Deleting sas.logon.zone ${zone_config_id}"
          curl -k -X DELETE ${INGRESS_URL}/configuration/configurations/${zone_config_id} \
          -H "Authorization: Bearer $ACCESS_TOKEN"
     fi
     return
    fi
     
    curl -k -X POST ${INGRESS_URL}/configuration/configurations \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/vnd.sas.collection+json" \
     -d '
     {
          "version": 2,
          "items": [
          {
               "metadata": {
                    "services": [
                         "SASLogon"
                    ],
               "isDefault": false,
               "mediaType": "application/vnd.sas.configuration.config.sas.logon.oauth.providers+json;version=1",
               "tenant": null
               },
               "authUrl": "'${oauthAuthUrl}'",
               "discoveryUrl": "'${oauthDiscoveryUrl}'",
               "tokenUrl": "'${oauthTokenUrl}'",
               "relyingPartyId": "'${oauthClientId}'",
               "relyingPartySecret": "'${oauthClientSecret}'",
               "name": "'${oauthName}'",
               "attributeMappings.user_name": "'${oauthAttributeMappingUserName}'",
               "scopes": "'${oauthScopes}'",
               "responseType": "'${oauthResponseType}'"
          }
          ]
     }'| jq

    #configure logon page bypass
    curl -k -X POST ${INGRESS_URL}/configuration/configurations \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/vnd.sas.collection+json" \
     -d '
     {
          "version": 2,
          "items": [
          {
               "metadata": {
                    "services": [
                         "SASLogon"
                    ],
               "isDefault": false,
               "mediaType": "application/vnd.sas.configuration.config.sas.logon.zone+json;version=2",
               "tenant": null
               },
               "defaultIdentityProvider": "'${oauthName}'"
          }
          ]
     }'| jq
    
}
