#!/bin/bash

# Path to your YAML files (can be directory or single file)
YAML_PATH="$1"

echo "Resources using 1001 in runAsUser, runAsGroup, or fsGroup:"

for file in $YAML_PATH; do
    ./tools/yq eval-all '
      . as $doc |
      select(
        (.spec.template.spec.securityContext.runAsUser == 1001) or
        (.spec.template.spec.securityContext.runAsGroup == 1001) or
        (.spec.template.spec.securityContext.fsGroup == 1001) or
        (.spec.securityContext.runAsUser == 1001) or
        (.spec.securityContext.runAsGroup == 1001) or
        (.spec.securityContext.fsGroup == 1001)
      ) |
      .metadata.name + " (" + (.kind // "UnknownKind") + ")"
    ' "$file"
done
