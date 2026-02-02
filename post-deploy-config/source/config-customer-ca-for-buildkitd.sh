#!/bin/bash
set -euo pipefail

# 🧩 Require namespace as first argument
if [[ $# -lt 1 ]]; then
  echo "❌ Usage: $0 <namespace>"
  echo "Example: $0 my-namespace"
  exit 1
fi

NAMESPACE=$1

# Step 1: Get the ConfigMap name
CONFIGMAP=$(oc get configmap -n "$NAMESPACE" \
  --no-headers -o custom-columns=":metadata.name" \
  | grep '^sas-customer-provided-ca-certificates' \
  | head -n1)

if [[ -z "$CONFIGMAP" ]]; then
  echo "❌ No ConfigMap found starting with 'sas-customer-provided-ca-certificates' in namespace '$NAMESPACE'"
  exit 1
fi

echo "✅ Found ConfigMap: $CONFIGMAP"

# Step 2: Create patch YAML
PATCH_FILE=$(mktemp)
cat > "$PATCH_FILE" <<EOF
spec:
  template:
    spec:
      volumes:
        - name: ca-certificates
          configMap:
            name: $CONFIGMAP
      containers:
        - name: buildkitd
          volumeMounts:
            - name: ca-certificates
              mountPath: /etc/ssl/certs
EOF

# Step 3: Apply patch
echo "🔧 Patching deployment 'buildkitd' in namespace '$NAMESPACE'..."
oc patch deployment buildkitd -n "$NAMESPACE" --type=strategic --patch-file "$PATCH_FILE"

echo "✅ Successfully patched deployment 'buildkitd' with ConfigMap '$CONFIGMAP'"

rm -f "$PATCH_FILE"

