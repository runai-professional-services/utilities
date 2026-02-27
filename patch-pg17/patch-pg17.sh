#!/bin/bash
#
# Patch for Run:ai control-plane v2.24.51 + PostgreSQL 17 incompatibility
# Case: 01087689
#
# The check-postgres-readiness init container ships postgresql16-server,
# whose psql \l meta-command references d.daticulocale (renamed in PG17).
# This patch swaps the image to the CloudNativePG postgresql:17.5 image,
# which includes a PG17-compatible psql client and runs as non-root
# (compatible with OpenShift restricted SCCs).
#

NAMESPACE="${1:-runai-backend}"
IMAGE="${2:-ghcr.io/cloudnative-pg/postgresql:17.5}"

echo "=== Patching check-postgres-readiness image to $IMAGE in namespace: $NAMESPACE ==="
echo ""

PATCHED=0

PATCH_FILE=$(mktemp /tmp/pg17-patch-XXXXXX.json)
trap "rm -f $PATCH_FILE" EXIT

cat > "$PATCH_FILE" <<EOF
{
  "spec": {
    "template": {
      "spec": {
        "initContainers": [
          {
            "name": "check-postgres-readiness",
            "image": "$IMAGE",
            "securityContext": {
              "runAsNonRoot": true
            }
          }
        ]
      }
    }
  }
}
EOF

for resource in $(kubectl -n "$NAMESPACE" get deploy,statefulset -o name 2>/dev/null); do
  HAS_INIT=$(kubectl -n "$NAMESPACE" get "$resource" -o jsonpath='{.spec.template.spec.initContainers[?(@.name=="check-postgres-readiness")].name}' 2>/dev/null)

  if [ -n "$HAS_INIT" ]; then
    echo "Patching $resource ..."
    kubectl -n "$NAMESPACE" patch "$resource" --type=strategic -p "$(cat "$PATCH_FILE")"

    if [ $? -eq 0 ]; then
      echo "  -> Patched successfully"
      PATCHED=$((PATCHED + 1))
    else
      echo "  -> FAILED to patch"
    fi
  fi
done

echo ""
echo "=== Done. Patched: $PATCHED ==="
kubectl -n runai-backend delete pod keycloak-0
echo ""
echo "Pods will restart automatically. Monitor rollout with:"
echo "  kubectl -n $NAMESPACE get pods -w"
