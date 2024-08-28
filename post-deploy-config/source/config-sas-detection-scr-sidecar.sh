#!/usr/bin/env bash
oc patch deployment sas-detection --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/ports/0/containerPort", "value": 8777}]'
oc patch deployment sas-detection --patch-file sas-detection-patch.yaml
oc patch deployment sas-detection --patch-file scr-sidecar-patch.yaml