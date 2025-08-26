#!/bin/bash

# Usage: ./extract_1001_resources.sh site-2025.08.yaml

FILE="$1"

if [[ -z "$FILE" ]]; then
  echo "Usage: $0 <kubernetes-manifest.yaml>"
  exit 1
fi

echo "Resources using runAsUser/runAsGroup/fsGroup = 1001:"
echo "-----------------------------------------------------"

yq eval '
  select(
    .spec.securityContext.runAsUser == 1001 or
    .spec.securityContext.runAsGroup == 1001 or
    .spec.securityContext.fsGroup == 1001 or
    .spec.template.spec.securityContext.runAsUser == 1001 or
    .spec.template.spec.securityContext.runAsGroup == 1001 or
    .spec.template.spec.securityContext.fsGroup == 1001 or
    .spec.jobTemplate.spec.template.spec.securityContext.runAsUser == 1001 or
    .spec.jobTemplate.spec.template.spec.securityContext.runAsGroup == 1001 or
    .spec.jobTemplate.spec.template.spec.securityContext.fsGroup == 1001 or
    .template.spec.securityContext.runAsUser == 1001 or
    .template.spec.securityContext.runAsGroup == 1001 or
    .template.spec.securityContext.fsGroup == 1001 or
    (.spec.template.spec.containers[]?.securityContext.runAsUser == 1001) or
    (.spec.template.spec.containers[]?.securityContext.runAsGroup == 1001) or
    (.spec.template.spec.containers[]?.securityContext.fsGroup == 1001) or
    (.spec.template.spec.initContainers[]?.securityContext.runAsUser == 1001) or
    (.spec.template.spec.initContainers[]?.securityContext.runAsGroup == 1001) or
    (.spec.template.spec.initContainers[]?.securityContext.fsGroup == 1001) or
    (.template.spec.containers[]?.securityContext.runAsUser == 1001) or
    (.template.spec.containers[]?.securityContext.runAsGroup == 1001) or
    (.template.spec.containers[]?.securityContext.fsGroup == 1001) or
    (.template.spec.initContainers[]?.securityContext.runAsUser == 1001) or
    (.template.spec.initContainers[]?.securityContext.runAsGroup == 1001) or
    (.template.spec.initContainers[]?.securityContext.fsGroup == 1001)
  ) |
  .kind + " | " + .metadata.name + " | " + (.metadata.namespace // "default")
' "$FILE"

