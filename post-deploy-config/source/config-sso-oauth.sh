#!/usr/bin/env bash

config-sso-oauth() {
    echo "Entering ${FUNCNAME[0]}"
    #configure SSO OAUTH
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
    
}