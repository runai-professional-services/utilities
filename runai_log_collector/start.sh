#!/bin/bash

# Function to collect logs for a given namespace and output directory
collect_logs() {
  local NAMESPACE=$1
  local LOG_DIR=$2
  local LOGS_SUBDIR="$LOG_DIR/logs"
  mkdir -p "$LOGS_SUBDIR"
  PODS=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')
  for POD in $PODS; do
    CONTAINERS=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.spec.containers[*].name}')
    for CONTAINER in $CONTAINERS; do
      LOG_FILE="$LOGS_SUBDIR/${POD}_${CONTAINER}.log"
      echo "Collecting logs for Pod: $POD, Container: $CONTAINER"
      kubectl logs --timestamps $POD -c $CONTAINER -n $NAMESPACE > "$LOG_FILE"
    done
  done
}

# Namespaces to check
NAMESPACES=("runai" "runai-backend")

for NAMESPACE in "${NAMESPACES[@]}"; do
  kubectl get namespace "$NAMESPACE" >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "Namespace '$NAMESPACE' does not exist. Skipping."
    continue
  fi

  echo "Namespace '$NAMESPACE' exists. Extracting logs and info:"
  TIMESTAMP=$(date +%d-%m-%Y_%H-%M)
  LOG_NAME="$NAMESPACE-logs-$TIMESTAMP"
  LOG_DIR="./$LOG_NAME"
  LOG_ARCHIVE_NAME="$LOG_NAME.tar.gz"
  mkdir $LOG_DIR

  # Collect logs into logs subdirectory
  collect_logs $NAMESPACE $LOG_DIR

  # Collect extra info per namespace
  if [ "$NAMESPACE" == "runai" ]; then
    helm ls -A > "$LOG_DIR/helm_charts_list.txt"
    helm get values runai-cluster -n runai > "$LOG_DIR/helm-values_runai-cluster.yaml" 2>/dev/null
    kubectl -n runai get cm runai-public -o yaml > "$LOG_DIR/cm_runai-public.yaml" 2>/dev/null
    kubectl -n runai get pods -o wide > "$LOG_DIR/pod-list_runai.txt"
    kubectl get nodes -o wide > "$LOG_DIR/node-list.txt"
    kubectl -n runai get runaiconfig runai -o yaml > "$LOG_DIR/runaiconfig.yaml"
    kubectl -n runai get configs.engine.run.ai engine-config -o yaml > "$LOG_DIR/engine-config.yaml"
  elif [ "$NAMESPACE" == "runai-backend" ]; then
    kubectl -n runai-backend get pods -o wide > "$LOG_DIR/pod-list_runai-backend.txt"
    helm get values runai-backend -n runai-backend > "$LOG_DIR/helm-values_runai-backend.yaml" 2>/dev/null
  fi

  du -hs $LOG_DIR
  tar cvzf $LOG_ARCHIVE_NAME $LOG_DIR
  ls -lah $LOG_ARCHIVE_NAME
  rm -rf $LOG_DIR
  echo "Logs and info archived to $LOG_ARCHIVE_NAME"
done