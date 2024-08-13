# SFD Deployment Instructions

##### Table of Contents
- [Download SAS Deployment Assets](#Download-SAS-Deployment-Assets)
- [Download SAS Deployment manifest](#Download-SAS-Deployment-manifest)

## Download SAS Deployment Assets
Download the deployment assets from my.sas.com and unzip them in the current directory

## Download SAS Deployment Manifest
For POC only, since kustomize is not available, download site.yaml file provided by SAS into the current directory.

## Edit Environment properties
Edit [env.propertie](env.properties) to set the properties of the environment.
Environment properties 
|  Property Name               |    Description                            |
| -----------------            |  ---------------------------------------- |
| project                      | Name of the Openshift project where SFD will be deployed. Ex. cp-3353070    |
| siteYaml                     | Name of the deployment manifest yaml file or full path if not in current directory. Ex. site.yaml |

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
