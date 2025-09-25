#!/bin/bash

# Workload Info Dump Script
VERSION="2.0.0"

# Removed 'set -e' to allow script to continue when individual commands fail

usage() {
  echo "Workload Info Dump Script v${VERSION}"
  echo ""
  echo "Usage: $0 --project <PROJECT> --workload <WORKLOAD> --type <TYPE>"
  echo "       $0 --version"
  echo ""
  echo "Examples:"
  echo "  $0 --project test --type tw --workload test-train"
  echo "  $0 --project test --type iw --workload test-interactive"
  echo "  $0 --project test --type infw --workload test-inference"
  echo "  $0 --project test --type dinfw --workload test-distributed-inference"
  echo "  $0 --project test --type dw --workload test-distributed-training"
  echo "  $0 --project test --type ew --workload test-external"
  echo ""
  echo "Options:"
  echo "  --version    Show script version and exit"
  exit 1
}

# Parse arguments first to handle --version before kubectl checks
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
    --version)
      echo "Workload Info Dump Script v${VERSION}"
      exit 0
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

# Check if kubectl exists and is accessible
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    echo "Please install kubectl and ensure it's accessible"
    exit 1
fi
echo "✅ kubectl found and accessible"

# Test kubectl connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: kubectl cannot connect to cluster"
    echo "Please check your kubeconfig and cluster connectivity"
    exit 1
fi
echo "✅ kubectl can connect to cluster"

# Display script version
echo ""
echo "🔧 Workload Info Dump Script v${VERSION}"
echo "   Enhanced for resilient resource collection"
echo ""

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

# Function to get workload YAML
get_workload_yaml() {
  local workload="$1"
  local canonical_type="$2"
  local type_safe="$3"
  
  local workload_yaml="${workload}_${type_safe}_workload.yaml"
  echo "  📄 Getting $canonical_type YAML..." >&2
  if kubectl -n "$NAMESPACE" get "$canonical_type" "$workload" -o yaml > "$workload_yaml" 2>/dev/null; then
    echo "    ✅ Workload YAML retrieved" >&2
    echo "$workload_yaml"
  else
    echo "    ❌ Failed to retrieve Workload YAML (resource may not exist or be accessible)" >&2
    return 1
  fi
}

# Function to get RunAIJob YAML
get_runaijob_yaml() {
  local workload="$1"
  local type_safe="$2"
  
  local runaijob_yaml="${workload}_${type_safe}_runaijob.yaml"
  echo "  📄 Getting RunAIJob YAML..." >&2
  if kubectl -n "$NAMESPACE" get rj "$workload" -o yaml > "$runaijob_yaml" 2>/dev/null; then
    echo "    ✅ RunAIJob YAML retrieved" >&2
    echo "$runaijob_yaml"
  else
    echo "    ❌ Failed to retrieve RunAIJob YAML (resource may not exist or be accessible)" >&2
    return 1
  fi
}

# Function to get pod YAML
get_pod_yaml() {
  local workload="$1"
  local type_safe="$2"
  
  local pod_yaml="${workload}_${type_safe}_pod.yaml"
  echo "  📄 Getting Pod YAML..." >&2
  if kubectl -n "$NAMESPACE" get pod -l workloadName=$workload -o yaml > "$pod_yaml" 2>/dev/null; then
    echo "    ✅ Pod YAML retrieved" >&2
    echo "$pod_yaml"
  else
    echo "    ❌ Failed to retrieve Pod YAML (no pods found or not accessible)" >&2
    return 1
  fi
}

# Function to get podgroup YAML
get_podgroup_yaml() {
  local workload="$1"
  local type_safe="$2"
  
  local podgroup_yaml="${workload}_${type_safe}_podgroup.yaml"
  echo "  📄 Getting PodGroup YAML..." >&2
  if kubectl -n "$NAMESPACE" get pg -l workloadName=$workload -o yaml > "$podgroup_yaml" 2>/dev/null; then
    echo "    ✅ PodGroup YAML retrieved" >&2
    echo "$podgroup_yaml"
  else
    echo "    ❌ Failed to retrieve PodGroup YAML (resource may not exist or be accessible)" >&2
    return 1
  fi
}

# Function to get pod logs
get_pod_logs() {
  local workload="$1"
  local type_safe="$2"
  
  echo "  📄 Getting Pod Logs..." >&2
  
  # Get all pods for this workload
  local pods=$(kubectl -n "$NAMESPACE" get pod -l workloadName=$workload -o jsonpath='{.items[*].metadata.name}')
  
  if [[ -z "$pods" ]]; then
    echo "    ⚠️  No pods found for workload: $workload" >&2
    return 0
  fi
  
  local output_files=()
  
  # Iterate through each pod
  for pod in $pods; do
    echo "    🐳 Processing pod: $pod" >&2
    
    # Get all containers (including init containers) for this pod
    local containers=$(kubectl -n "$NAMESPACE" get pod "$pod" -o jsonpath='{.spec.initContainers[*].name} {.spec.containers[*].name}')
    
    # Iterate through each container
    for container in $containers; do
      local log_file="${workload}_${type_safe}_pod_logs_${container}.log"
      echo "      📝 Getting logs for container: $container" >&2
      
      kubectl -n "$NAMESPACE" logs "$pod" -c "$container" > "$log_file" 2>/dev/null
      if [[ $? -eq 0 ]]; then
        echo "        ✅ Container logs retrieved: $container" >&2
        output_files+=("$log_file")
      else
        echo "        ❌ Failed to retrieve logs for container: $container" >&2
      fi
    done
  done
  
  if [[ ${#output_files[@]} -gt 0 ]]; then
    echo "    ✅ Pod logs retrieved for ${#output_files[@]} containers" >&2
    printf '%s\n' "${output_files[@]}"
  else
    echo "    ❌ No container logs were successfully retrieved" >&2
    return 1
  fi
}

# Function to get KSVC YAML (for inference workloads)
get_ksvc_yaml() {
  local workload="$1"
  local type_safe="$2"
  
  local ksvc_spec="${workload}_${type_safe}_ksvc.yaml"
  echo "  📄 Getting KSVC YAML..." >&2
  if kubectl -n "$NAMESPACE" get ksvc "$workload" -o yaml > "$ksvc_spec" 2>/dev/null; then
    echo "    ✅ KSVC YAML retrieved" >&2
    echo "$ksvc_spec"
  else
    echo "    ❌ Failed to retrieve KSVC YAML (resource may not exist or be accessible)" >&2
    return 1
  fi
}

# Function to get pod descriptions for all pods in namespace
get_all_pods_describe() {
  local workload="$1"
  local type_safe="$2"
  
  local pod_describe_file="${workload}_${type_safe}_all_pods_describe.txt"
  echo "  📄 Getting pod descriptions for all pods in namespace..." >&2
  if kubectl -n "$NAMESPACE" describe pods > "$pod_describe_file" 2>/dev/null; then
    echo "    ✅ Pod descriptions retrieved" >&2
    echo "$pod_describe_file"
  else
    echo "    ❌ Failed to retrieve pod descriptions (no pods found or not accessible)" >&2
    return 1
  fi
}

# Function to get pod list for all pods in namespace
get_all_pods_list() {
  local workload="$1"
  local type_safe="$2"
  
  local pod_list_file="${workload}_${type_safe}_all_pods_list.txt"
  echo "  📄 Getting pod list for all pods in namespace..." >&2
  if kubectl -n "$NAMESPACE" get pods -o wide > "$pod_list_file" 2>/dev/null; then
    echo "    ✅ Pod list retrieved" >&2
    echo "$pod_list_file"
  else
    echo "    ❌ Failed to retrieve pod list (no pods found or not accessible)" >&2
    return 1
  fi
}

# Function to get all ConfigMaps in namespace
get_all_configmaps() {
  local workload="$1"
  local type_safe="$2"
  
  local configmap_file="${workload}_${type_safe}_all_configmaps.yaml"
  echo "  📄 Getting all ConfigMaps in namespace..." >&2
  if kubectl -n "$NAMESPACE" get configmap -o yaml > "$configmap_file" 2>/dev/null; then
    echo "    ✅ ConfigMaps retrieved" >&2
    echo "$configmap_file"
  else
    echo "    ❌ Failed to retrieve ConfigMaps (no configmaps found or not accessible)" >&2
    return 1
  fi
}

# Function to get all PVCs in namespace
get_all_pvcs() {
  local workload="$1"
  local type_safe="$2"
  
  local pvc_file="${workload}_${type_safe}_all_pvcs.yaml"
  echo "  📄 Getting all PVCs in namespace..." >&2
  if kubectl -n "$NAMESPACE" get pvc -o yaml > "$pvc_file" 2>/dev/null; then
    echo "    ✅ PVCs retrieved" >&2
    echo "$pvc_file"
  else
    echo "    ❌ Failed to retrieve PVCs (no PVCs found or not accessible)" >&2
    return 1
  fi
}

# Arguments have already been parsed and validated above

# Lookup namespace from project
NAMESPACE=$(kubectl get ns -l runai/queue="$PROJECT" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "$NAMESPACE" ]]; then
  echo "❌ No namespace found for project: $PROJECT"
  echo "Please check that the project exists and is accessible"
  exit 1
fi

echo "Collecting info dump for workload '$WORKLOAD' ($TYPE) in project $PROJECT"
echo ""

# Validate type
CANONICAL_TYPE=$(get_canonical_type "$TYPE")
if [[ -z "$CANONICAL_TYPE" ]]; then
  echo "Invalid type: $TYPE"
  usage
fi

# Output file names
TYPE_SAFE=$(echo "$TYPE" | tr '/' '_')
OUTPUT_FILES=()

# Add timestamp and version for archive
TIMESTAMP=$(date +"%Y_%m_%d-%H_%M")
VERSION_SAFE=$(echo "$VERSION" | tr '.' '_')
ARCHIVE="${PROJECT}_${TYPE_SAFE}_${WORKLOAD}_v${VERSION_SAFE}_${TIMESTAMP}.tar.gz"

# Execute all collection functions
echo "📁 Starting collection process..."
echo ""

# Get workload YAML
if workload_yaml=$(get_workload_yaml "$WORKLOAD" "$CANONICAL_TYPE" "$TYPE_SAFE"); then
  OUTPUT_FILES+=("$workload_yaml")
fi

# Get runaijob YAML
if runaijob_yaml=$(get_runaijob_yaml "$WORKLOAD" "$TYPE_SAFE"); then
  OUTPUT_FILES+=("$runaijob_yaml")
fi

# Get pod YAML
if pod_yaml=$(get_pod_yaml "$WORKLOAD" "$TYPE_SAFE"); then
  OUTPUT_FILES+=("$pod_yaml")
fi

# Get podgroup YAML
if podgroup_yaml=$(get_podgroup_yaml "$WORKLOAD" "$TYPE_SAFE"); then
  OUTPUT_FILES+=("$podgroup_yaml")
fi

# Get pod logs
if pod_logs_output=$(get_pod_logs "$WORKLOAD" "$TYPE_SAFE"); then
  # Add each log file to the output files array
  while IFS= read -r log_file; do
    if [[ -n "$log_file" ]]; then
      OUTPUT_FILES+=("$log_file")
    fi
  done <<< "$pod_logs_output"
fi

# Get ksvc for inference workloads
if [[ "$CANONICAL_TYPE" == "inferenceworkloads" ]]; then
  if ksvc_spec=$(get_ksvc_yaml "$WORKLOAD" "$TYPE_SAFE"); then
    OUTPUT_FILES+=("$ksvc_spec")
  fi
fi

# Get pod descriptions for all pods in namespace
if pod_describe_output=$(get_all_pods_describe "$WORKLOAD" "$TYPE_SAFE"); then
  OUTPUT_FILES+=("$pod_describe_output")
fi

# Get pod list for all pods in namespace
if pod_list_output=$(get_all_pods_list "$WORKLOAD" "$TYPE_SAFE"); then
  OUTPUT_FILES+=("$pod_list_output")
fi

# Get all ConfigMaps in namespace
if configmap_output=$(get_all_configmaps "$WORKLOAD" "$TYPE_SAFE"); then
  OUTPUT_FILES+=("$configmap_output")
fi

# Get all PVCs in namespace
if pvc_output=$(get_all_pvcs "$WORKLOAD" "$TYPE_SAFE"); then
  OUTPUT_FILES+=("$pvc_output")
fi

echo ""
echo "📊 Collection Summary:"
echo "  Total files collected: ${#OUTPUT_FILES[@]}"
if [[ ${#OUTPUT_FILES[@]} -eq 0 ]]; then
  echo "  ⚠️  No files were successfully collected."
  echo "  This may indicate that the workload doesn't exist or resources are not accessible."
  echo "  Please check the workload name, type, and your permissions."
  exit 1
fi

echo "  Files collected:"
for file in "${OUTPUT_FILES[@]}"; do
  echo "    - $file"
done

# Archive the files
echo ""
echo "📦 Creating archive..."
if tar -czf "$ARCHIVE" "${OUTPUT_FILES[@]}" 2>/dev/null; then
  echo "  ✅ Archive created: $ARCHIVE"
  
  # Clean up individual files
  echo ""
  echo "🧹 Cleaning up individual files..."
  for file in "${OUTPUT_FILES[@]}"; do
    if [[ -f "$file" ]]; then
      rm "$file"
      echo "  🗑️  Deleted: $file"
    fi
  done
  echo ""
  echo "✅ Cleanup completed. Only archive remains: $ARCHIVE"
else
  echo "  ❌ Failed to create archive. Individual files preserved."
  echo "  You can manually archive the following files:"
  for file in "${OUTPUT_FILES[@]}"; do
    echo "    - $file"
  done
  exit 1
fi
