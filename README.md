# SFD Deployment Instructions

##### Table of Contents
- [Download SAS Deployment Assets](#Download-SAS-Deployment-Assets)
- [Edit Environment properties](#Edit-Environment-Properties)
- [Customer Provided CA certificates](#Customer-Provided-CA-certificates)
- [Create Deployment manifest](#Create-Deployment-manifest)
- [Pre Upgrade Steps](#Pre-Upgrade-Steps)
- [Deploy SFD](#Deploy-SFD)
- [Post Deploy Steps](#Post-Deploy-Steps)
- [Post Upgrade Steps](#Post-Upgrade-Steps)
- [Uninstall SFD](#Uninstall-SFD)

## Download SAS Deployment Assets
Download the deployment assets from my.sas.com and unzip them in the downloads directory or create a symlink name downloads for your deployment assets in a different location.

## Edit Environment Properties
Copy the sample environment properties file from [examples/sample-properties.env](examples/sample-properties.env) as properties.env in current directory and edit it to set the properties for the environment.
Environment properties 
|  Property Name               |    Description                            |
| -----------------            |  ---------------------------------------- |
| project                      | Name of the Openshift project where SFD will be deployed. Ex. cp-3353070    |

## Customer Provided CA certificates
Create a directory named "ca-certificates" in the current directory and place the necessary customer provided CA certificates in pem format. The file extension should be .pem

## Create Deployment Manifest
This script will create the deployment manifest (site.yaml) required to deploy SFD on openshift
```bash
./create-site-yaml.sh
```

## Pre Upgrade Steps
If you are doing an upgrade, read the deployment notes published by SAS to see if there are any steps required to upgrade https://go.documentation.sas.com/doc/en/itopscdc/v_058/dplynotes/titlepage.htm

> [!NOTE]
> The upgrade scripts `pre-upgrade-to_{cadence}.sh` and `post-upgrade-to_{cadence}.sh` are typically generated during the deployment process or provided in specific SAS maintenance releases. If they are not present in your `sfd-install-scripts` directory, refer to the official SAS documentation for manual upgrade steps.

```bash
cd sfd-install-scripts
#{cadence} is either 2024.09, 2024.10 or 2024.11
# ./pre-upgrade-to_{cadence}.sh
```

## Deploy SFD
This will create and bind the necessary SCCs (Security Context Constraints) and deploy all the resources required for SFD by applying the Manifest. This should be run by cluster admin.
```bash
cd sfd-install-scripts
./install-sfd.sh
```

## Post Deploy Steps
This step will configure Oauth, Rules/model deployment destination, Redis Credentials for Advanced Lists and Rules Studio UI.
The `post-deploy-config.sh` script is a dispatcher. You run it by passing the desired function name as an argument.

```bash
# Example usage:
# ./post-deploy-config.sh config-sso-oauth
```
| Function            |   Description    |
| --------------------- | ------------------------- |
| config-sso-oauth    | Configures Oauth with values defined in properties.env |
| config-model-publish-dest  | Configures container registry defined in properties.env as the destination for rules and model in SFD  |
| config-list-data-redis    | Configures Advanced Lists with Redis credentials defined in properties.env   |
| config-sfd-rules-studio  | Configures Rules Studio UI with privileges for the sfdAdminUserId defined in properties.env and hardcoded messageClassification/Organization/Projects etc. Read the script [post-deploy-config/source/config-sfd-rules-studio.sh](post-deploy-config/source/config-sfd-rules-studio.sh) for more details |
| config-query-internal-postgres | Executes SQL queries against the internal Postgres database |
| config-internal-redis | Configures the internal Redis instance |
| config-license-renew | Renews the SAS license with a provided license file |

Ensure sfdAdminUserId property is set to an active directory user that needs SFD admin privileges. This is the user that will be used to configure SFD with the post-deploy-config script.

```bash
cd post-deploy-config
./post-deploy-config.sh <function-name>
```

## Post Upgrade Steps
If you are doing an upgrade, read the deployment notes published by SAS to see if there are any steps required to upgrade https://go.documentation.sas.com/doc/en/itopscdc/v_058/dplynotes/titlepage.htm

The post upgrade steps for 2024.08 to 2024.09 or 2024.10 or 2024.11 have been scripted. The script should be available in sfd-install-scripts after you create deployment manifests. This should be run by cluster admin.
```bash
> [!NOTE]
> If the upgrade scripts are not found in `sfd-install-scripts`, manual intervention may be required as per SAS documentation.

```bash
cd sfd-install-scripts
#{cadence} is either 2024.09, 2024.10 or 2024.11
# ./post-upgrade-to_{cadence}.sh
```

## Uninstall SFD
This will remove all the SCCs and SFD resources from openshift. This should be run by cluster admin.
```bash
./uninstall-sfd.sh
```
