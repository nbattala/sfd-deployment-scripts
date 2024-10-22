# SFD Deployment Instructions

##### Table of Contents
- [Download SAS Deployment Assets](#Download-SAS-Deployment-Assets)
- [Edit Environment properties](#Edit-Environment-Properties)
- [Customer Provided CA certificates](#Customer-Provided-CA-certificates)
- [Create Deployment manifest](#Create-Deployment-manifest)
- [Deploy SFD](#Deploy-SFD)
- [Uninstall SFD](#Uninstall-SFD)

## Download SAS Deployment Assets
Download the deployment assets from my.sas.com and unzip them in the downloads directory or create a symlink name downloads for your deployment assets in a different location.

## Edit Environment Properties
Copy the sample environment properties file from [examples/sample-properties.env](examples/sample-properties.env) as properties.env in current directory and edit it to set the properties for the environment.
Environment properties 
|  Property Name               |    Description                            |
| -----------------            |  ---------------------------------------- |
| project                      | Name of the Openshift project where SFD will be deployed. Ex. cp-3353070    |
| siteYaml                     | Name of the deployment manifest yaml file or full path if not in current directory. Ex. site.yaml |

## Customer Provided CA certificates
Create a directory named "ca-certificates" in the current directory and place the necessary customer provided CA certificates in pem format. The file extension should be .pem

## Create Deployment Manifest
This script will create the deployment manifest (site.yaml) required to deploy SFD on openshift
```bash
./create-site-yaml.sh
```

## Deploy SFD
This will create and bind the necessary SCCs (Security Context Constraints) and deploy all the resources required for SFD by applying the Manifest
```bash
./install-sfd.sh
```

## Uninstall SFD
This will remove all the SCCs and SFD resources from openshift. 
```bash
./uninstall-sfd.sh
```
