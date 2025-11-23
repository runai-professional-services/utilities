#!/bin/bash

NAMESPACE="runai-backend"
OLD_REGISTRY="docker.io/bitnami"
NEW_REGISTRY="docker.io/bitnamilegacy"

echo "=== Checking for images with $OLD_REGISTRY ==="
echo ""

resources=$(kubectl get deploy,sts,ds -n $NAMESPACE -o name)

for resource in $resources; do
  needs_update=$(kubectl get $resource -n $NAMESPACE -o json | jq -r '
    ([.spec.template.spec.containers[]?, .spec.template.spec.initContainers[]?] | 
    map(select(.image | contains("'$OLD_REGISTRY'"))) | length)')
  
  if [ "$needs_update" -gt 0 ]; then
    echo "📦 $resource"
    kubectl get $resource -n $NAMESPACE -o json | jq -r '
      (.spec.template.spec.containers[]? | select(.image | contains("'$OLD_REGISTRY'")) | "  ✓ container: \(.name) = \(.image)"),
      (.spec.template.spec.initContainers[]? | select(.image | contains("'$OLD_REGISTRY'")) | "  ✓ initContainer: \(.name) = \(.image)")'
    echo ""
  fi
done

echo ""
read -p "Proceed with updates? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
  for resource in $resources; do
    needs_update=$(kubectl get $resource -n $NAMESPACE -o json | jq -r '
      ([.spec.template.spec.containers[]?, .spec.template.spec.initContainers[]?] | 
      map(select(.image | contains("'$OLD_REGISTRY'"))) | length)')
    
    if [ "$needs_update" -gt 0 ]; then
      echo "Patching $resource..."
      
      patch_data=$(kubectl get $resource -n $NAMESPACE -o json | jq '{
        spec: {
          template: {
            spec: {
              containers: [.spec.template.spec.containers[]? | 
                .image |= sub("'$OLD_REGISTRY'"; "'$NEW_REGISTRY'")],
              initContainers: ([.spec.template.spec.initContainers[]? | 
                .image |= sub("'$OLD_REGISTRY'"; "'$NEW_REGISTRY'")] | if length == 0 then null else . end)
            }
          }
        }
      } | if .spec.template.spec.initContainers == null then del(.spec.template.spec.initContainers) else . end')
      
      echo "$patch_data" | kubectl patch $resource -n $NAMESPACE --type=strategic -p "$patch_data"
    fi
  done
  echo "✅ Done!"
fi