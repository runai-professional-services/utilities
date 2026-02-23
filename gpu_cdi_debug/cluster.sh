#!/bin/bash
# Run from a machine with kubectl (and helm) access to the cluster.
# Creates output dir, collects GPU Operator / cluster info, then archives it.

OUT=~/runai-cdi-collect-$(date +%Y%m%d)
mkdir -p "$OUT"
cd "$OUT" || exit 1

# ClusterPolicy
kubectl get clusterpolicy cluster-policy -n gpu-operator -o yaml > "$OUT/clusterpolicy.yaml" 2>&1

# Helm values
helm get values gpu-operator -n gpu-operator -o yaml > "$OUT/helm_values.yaml" 2>&1

# Toolkit DaemonSet
kubectl get daemonset -n gpu-operator -l app=nvidia-container-toolkit-daemonset -o yaml > "$OUT/toolkit_daemonset.yaml" 2>&1

# Device plugin DaemonSet
kubectl get daemonset -n gpu-operator -l app=nvidia-device-plugin-daemonset -o yaml > "$OUT/device_plugin_daemonset.yaml" 2>&1

# Toolkit pod logs (set NODE_NAME to the GPU node where you ran node.sh)
NODE_NAME="${NODE_NAME:-ip-172-20-10-160}"
TOOLKIT_POD=$(kubectl get pods -n gpu-operator -l app=nvidia-container-toolkit-daemonset -o jsonpath='{.items[?(@.spec.nodeName=="'"$NODE_NAME"'")].metadata.name}')
if [ -n "$TOOLKIT_POD" ]; then
  kubectl logs -n gpu-operator "$TOOLKIT_POD" -c nvidia-container-toolkit-ctr --tail=500 > "$OUT/toolkit_pod_logs.txt" 2>&1
else
  echo "No toolkit pod found on node $NODE_NAME" > "$OUT/toolkit_pod_logs.txt" 2>&1
fi

echo "Cluster collection done. Outputs in $OUT"
ls -la "$OUT"

# Package to archive
ARCHIVE="${OUT}.tar.gz"
tar czvf "$ARCHIVE" -C "$(dirname "$OUT")" "$(basename "$OUT")"
echo "Archive created: $ARCHIVE"
ls -la "$ARCHIVE"
