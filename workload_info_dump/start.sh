#!/bin/bash

# Workload Info Dump Script
VERSION="2.3.0"

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
echo "   Enhanced for resilient resource collection with unified pod processing"
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
    # Check if file is empty or contains no valid content
    if [[ ! -s "$runaijob_yaml" ]]; then
      echo "    ❌ RunAIJob resource returned empty content" >&2
      rm -f "$runaijob_yaml" 2>/dev/null
      return 1
    fi
    echo "    ✅ RunAIJob YAML retrieved" >&2
    echo "$runaijob_yaml"
  else
    echo "    ❌ Failed to retrieve RunAIJob YAML (resource may not exist or be accessible)" >&2
    # Clean up empty file if it was created
    rm -f "$runaijob_yaml" 2>/dev/null
    return 1
  fi
}

# Function to get pods and containers information (centralized discovery)
get_pods_and_containers_info() {
  local workload="$1"
  
  # Get all pods for this workload in one call
  local pods_json=$(kubectl -n "$NAMESPACE" get pod -l workloadName=$workload -o json 2>/dev/null)
  
  if [[ -z "$pods_json" ]] || [[ "$pods_json" == "null" ]]; then
    echo "    ❌ No pods found for workload: $workload" >&2
    return 1
  fi
  
  # Extract pod names and containers info using jq for efficiency
  if command -v jq &> /dev/null; then
    # Use jq if available for better JSON parsing
    echo "$pods_json" | jq -r '.items[] | "\(.metadata.name)|\([(.spec.initContainers//[])[]?.name, .spec.containers[].name] | join(" "))"'
  else
    # Fallback to kubectl jsonpath if jq is not available
    local pod_names=$(echo "$pods_json" | kubectl get -f - -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    for pod in $pod_names; do
      local containers=$(kubectl -n "$NAMESPACE" get pod "$pod" -o jsonpath='{.spec.initContainers[*].name} {.spec.containers[*].name}' 2>/dev/null)
      echo "${pod}|${containers}"
    done
  fi
}

# Unified function to process all pod operations efficiently (OPTIMIZED)
process_pods_unified() {
  local workload="$1"
  local type_safe="$2"
  local pods_info="$3"  # Pre-fetched pod information
  
  echo "  📄 Processing all pod operations..." >&2
  
  if [[ -z "$pods_info" ]]; then
    echo "    ❌ No pod information provided" >&2
    return 1
  fi
  
  local output_files=()
  local total_pods=0
  local total_containers=0
  local total_nvidia_files=0
  
  # Parse pre-fetched pod information and process each pod completely
  while IFS='|' read -r pod containers; do
    [[ -z "$pod" ]] && continue
    ((total_pods++))
    
    echo "    🐳 Processing pod: $pod" >&2
    
    # 1. Get Pod YAML
    local pod_yaml="${workload}_${type_safe}_pod_${pod}.yaml"
    if kubectl -n "$NAMESPACE" get pod "$pod" -o yaml > "$pod_yaml" 2>/dev/null; then
      echo "      ✅ Pod YAML retrieved: $pod" >&2
      output_files+=("$pod_yaml")
    else
      echo "      ❌ Failed to retrieve YAML for pod: $pod" >&2
    fi
    
    # 2. Get Pod Description
    local pod_describe_file="${workload}_${type_safe}_pod_${pod}_describe.txt"
    if kubectl -n "$NAMESPACE" describe pod "$pod" > "$pod_describe_file" 2>/dev/null; then
      echo "      ✅ Pod description retrieved: $pod" >&2
      output_files+=("$pod_describe_file")
    else
      echo "      ❌ Failed to retrieve description for pod: $pod" >&2
    fi
    
    # 3. Process all containers for this pod (logs + nvidia-smi)
    for container in $containers; do
      [[ -z "$container" ]] && continue
      ((total_containers++))
      
      # Get container logs
      local log_file="${workload}_${type_safe}_pod_${pod}_logs_${container}.log"
      if kubectl -n "$NAMESPACE" logs "$pod" -c "$container" > "$log_file" 2>/dev/null; then
        echo "      ✅ Logs retrieved: $container (pod: $pod)" >&2
        output_files+=("$log_file")
      else
        echo "      ⚠️  Failed to retrieve logs: $container (pod: $pod)" >&2
      fi
      
      # Get nvidia-smi output
      local nvidia_file="${workload}_${type_safe}_pod_${pod}_nvidia_smi_${container}.txt"
      if kubectl -n "$NAMESPACE" exec "$pod" -c "$container" -- nvidia-smi > "$nvidia_file" 2>/dev/null; then
        echo "      ✅ nvidia-smi retrieved: $container (pod: $pod)" >&2
        output_files+=("$nvidia_file")
        ((total_nvidia_files++))
      else
        # Clean up empty file if command failed
        rm -f "$nvidia_file" 2>/dev/null
      fi
    done
    
  done <<< "$pods_info"
  
  # Summary output
  if [[ ${#output_files[@]} -gt 0 ]]; then
    echo "    ✅ Pod processing completed:" >&2
    echo "      - ${total_pods} pods processed" >&2
    echo "      - ${total_containers} containers processed" >&2
    echo "      - ${total_nvidia_files} nvidia-smi outputs retrieved" >&2
    echo "      - ${#output_files[@]} total files generated" >&2
    printf '%s\n' "${output_files[@]}"
  else
    echo "    ❌ No pod information was successfully retrieved" >&2
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

# Centralized pod and container discovery (OPTIMIZATION: single kubectl call)
echo "  🔍 Discovering pods and containers..." >&2
PODS_INFO=$(get_pods_and_containers_info "$WORKLOAD")
if [[ $? -eq 0 && -n "$PODS_INFO" ]]; then
  echo "    ✅ Pod and container information discovered" >&2
  
  # Process all pod operations in unified manner (MAJOR OPTIMIZATION)
  if pod_output=$(process_pods_unified "$WORKLOAD" "$TYPE_SAFE" "$PODS_INFO"); then
    # Add each file to the output files array
    while IFS= read -r output_file; do
      if [[ -n "$output_file" ]]; then
        OUTPUT_FILES+=("$output_file")
      fi
    done <<< "$pod_output"
  fi
else
  echo "    ⚠️  No pods found for workload or discovery failed. Skipping pod-related operations." >&2
fi

# Get podgroup YAML
if podgroup_yaml=$(get_podgroup_yaml "$WORKLOAD" "$TYPE_SAFE"); then
  OUTPUT_FILES+=("$podgroup_yaml")
fi

# Get ksvc for inference workloads
if [[ "$CANONICAL_TYPE" == "inferenceworkloads" ]]; then
  if ksvc_spec=$(get_ksvc_yaml "$WORKLOAD" "$TYPE_SAFE"); then
    OUTPUT_FILES+=("$ksvc_spec")
  fi
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
    fi
  done
  echo "✅ Cleanup completed. Only archive remains: $ARCHIVE"
else
  echo "  ❌ Failed to create archive. Individual files preserved."
  echo "  You can manually archive the following files:"
  for file in "${OUTPUT_FILES[@]}"; do
    echo "    - $file"
  done
  exit 1
fi

