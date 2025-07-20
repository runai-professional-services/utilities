#!/bin/bash

set -e

# Function to map type aliases to canonical k8s resource names
get_canonical_type() {
  case "$1" in
    dinfw|distributedinferenceworkloads)
      echo "distributedinferenceworkloads" ;;
    dw|distributedworkloads)
      echo "distributedworkloads" ;;
    ew|externalworkloads)
      echo "externalworkloads" ;;
    infw|inferenceworkloads)
      echo "inferenceworkloads" ;;
    iw|interactiveworkloads)
      echo "interactiveworkloads" ;;
    tw|trainingworkloads)
      echo "trainingworkloads" ;;
    *)
      echo "" ;;
  esac
}

usage() {
  echo "Usage: $0 --project <PROJECT> --workload <WORKLOAD> --type <TYPE>"
  echo "Example: $0 --project test --type tw --workload test-train"
  echo "Example: $0 --project test --type iw --workload test-interactive"
  echo "Example: $0 --project test --type infw --workload test-inference"
  echo "Example: $0 --project test --type dinfw --workload test-distributed-inference"
  echo "Example: $0 --project test --type dw --workload test-distributed-training"
  echo "Example: $0 --project test --type ew --workload test-external"
  exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --project)
      PROJECT="$2"
      shift; shift
      ;;
    --workload)
      WORKLOAD="$2"
      shift; shift
      ;;
    --type)
      TYPE="$2"
      shift; shift
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      ;;
  esac
done

# Validate required arguments

if [[ -z "$PROJECT" || -z "$WORKLOAD" || -z "$TYPE" ]]; then
  usage
fi

# Lookup namespace from project
NAMESPACE=$(kubectl get ns -l runai/queue="$PROJECT" -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$NAMESPACE" ]]; then
  echo "No namespace found for project: $PROJECT"
  exit 1
fi

echo "Collecting info dump for workload '$WORKLOAD' ($TYPE) in project $PROJECT"

# Validate type
CANONICAL_TYPE=$(get_canonical_type "$TYPE")
if [[ -z "$CANONICAL_TYPE" ]]; then
  echo "Invalid type: $TYPE"
  usage
fi

# Output file names
TYPE_SAFE=$(echo "$TYPE" | tr '/' '_')
OUTPUT_FILES=()

# Add timestamp for archive
TIMESTAMP=$(date +"%Y_%m_%d-%H_%M")
ARCHIVE="${PROJECT}_${TYPE_SAFE}_${WORKLOAD}_${TIMESTAMP}.tar.gz"

# Run kubectl commands

# Get workload YAML
workload_yaml="${WORKLOAD}_${TYPE_SAFE}_workload.yaml"
echo "Getting $CANONICAL_TYPE $WORKLOAD as workload_yaml..."
kubectl -n "$NAMESPACE" get "$CANONICAL_TYPE" "$WORKLOAD" -o yaml > "$workload_yaml"
if [[ $? -eq 0 ]]; then
  echo "Workload YAML successfully retrieved."
else
  echo "Failed to retrieve Workload YAML."; exit 1
fi
OUTPUT_FILES+=("$workload_yaml")

# Get runaijob YAML
runaijob_yaml="${WORKLOAD}_${TYPE_SAFE}_runaijob.yaml"
echo "Getting rj $WORKLOAD as runaijob_yaml..."
kubectl -n "$NAMESPACE" get rj "$WORKLOAD" -o yaml > "$runaijob_yaml"
if [[ $? -eq 0 ]]; then
  echo "RunAIJob YAML successfully retrieved."
else
  echo "Failed to retrieve RunAIJob YAML."; exit 1
fi
OUTPUT_FILES+=("$runaijob_yaml")

# Get pod YAML
pod_yaml="${WORKLOAD}_${TYPE_SAFE}_pod.yaml"
echo "Getting pods with label workloadName=$WORKLOAD as pod_yaml..."
kubectl -n "$NAMESPACE" get pod -l workloadName=$WORKLOAD -o yaml > "$pod_yaml"
if [[ $? -eq 0 ]]; then
  echo "Pod YAML successfully retrieved."
else
  echo "Failed to retrieve Pod YAML."; exit 1
fi
OUTPUT_FILES+=("$pod_yaml")

# Get podgroup YAML
podgroup_yaml="${WORKLOAD}_${TYPE_SAFE}_podgroup.yaml"
echo "Getting podgroups (pg) with label workloadName=$WORKLOAD as podgroup_yaml..."
kubectl -n "$NAMESPACE" get pg -l workloadName=$WORKLOAD -o yaml > "$podgroup_yaml"
if [[ $? -eq 0 ]]; then
  echo "PodGroup YAML successfully retrieved."
else
  echo "Failed to retrieve PodGroup YAML."; exit 1
fi
OUTPUT_FILES+=("$podgroup_yaml")

# Get pod logs
pod_logs="${WORKLOAD}_${TYPE_SAFE}_pod_logs.txt"
echo "Getting logs for all pods with label workloadName=$WORKLOAD as pod_logs..."
kubectl -n "$NAMESPACE" logs -l workloadName=$WORKLOAD > "$pod_logs"
if [[ $? -eq 0 ]]; then
  echo "Pod logs successfully retrieved."
else
  echo "Failed to retrieve pod logs."; exit 1
fi
OUTPUT_FILES+=("$pod_logs")

# Get ksvc for inference workloads
if [[ "$CANONICAL_TYPE" == "inferenceworkloads" ]]; then
  ksvc_spec="${WORKLOAD}_${TYPE_SAFE}_ksvc.yaml"
  echo "Getting ksvc $WORKLOAD as ksvc_spec..."
  kubectl -n "$NAMESPACE" get ksvc "$WORKLOAD" -o yaml > "$ksvc_spec"
  if [[ $? -eq 0 ]]; then
    echo "KSVC YAML successfully retrieved."
  else
    echo "Failed to retrieve KSVC YAML."; exit 1
  fi
  OUTPUT_FILES+=("$ksvc_spec")
fi

# Add more commands here as needed, appending their output files to OUTPUT_FILES
# Example:
# kubectl -n "$NAMESPACE" get pod "$WORKLOAD" -o yaml > "${WORKLOAD}_pod.yaml"
# OUTPUT_FILES+=("${WORKLOAD}_pod.yaml")

# Archive the files
tar -czf "$ARCHIVE" "${OUTPUT_FILES[@]}"

echo "Archive created: $ARCHIVE"
