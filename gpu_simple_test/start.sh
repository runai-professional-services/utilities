#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

POD_NAME="gpu-test"
NAMESPACE="${NAMESPACE:-default}"
TIMEOUT="${TIMEOUT:-300}"
GPU_IMAGE="${GPU_IMAGE:-nvidia/cuda:11.8.0-base-ubuntu22.04}"
OUTPUT_DIR="gpu-test-results-$(date +%Y%m%d-%H%M%S)"
ARCHIVE_NAME="${OUTPUT_DIR}.tar.gz"
TEMP_YAML="/tmp/gpu-test-${RANDOM}.yaml"

echo -e "${GREEN}=== GPU Simple Test Script ===${NC}"
echo "Pod Name: $POD_NAME"
echo "Namespace: $NAMESPACE"
echo "Timeout: ${TIMEOUT}s"
echo "GPU Image: $GPU_IMAGE"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create the pod YAML dynamically
cat > "$TEMP_YAML" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
spec:
  restartPolicy: Never
  containers:
  - name: cuda
    image: $GPU_IMAGE
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

# Clean up any existing pod
echo -e "${YELLOW}Checking for existing pod...${NC}"
if kubectl get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo -e "${YELLOW}Deleting existing pod...${NC}"
    kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --ignore-not-found=true
    # Wait for pod to be deleted
    kubectl wait --for=delete pod/"$POD_NAME" -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
    sleep 2
fi

# Create the pod
echo -e "${GREEN}Creating GPU test pod...${NC}"
kubectl apply -f "$TEMP_YAML" -n "$NAMESPACE"

# Monitor pod status
echo -e "${YELLOW}Monitoring pod status...${NC}"
START_TIME=$(date +%s)
LAST_MESSAGE=""
SHOWN_SCHEDULING=false
SHOWN_PULLING=false

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ $ELAPSED -gt $TIMEOUT ]; then
        echo -e "${RED}Timeout reached (${TIMEOUT}s)${NC}"
        POD_STATUS="Timeout"
        break
    fi
    
    # Get pod phase
    POD_PHASE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    
    # Get container state and reason for better visibility
    CONTAINER_STATE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].state}' 2>/dev/null || echo "{}")
    CONTAINER_REASON=""
    
    # Check if pod is still pending (no container status yet)
    if [ "$POD_PHASE" == "Pending" ] && [ -z "$(echo $CONTAINER_STATE | grep -E 'waiting|terminated|running')" ]; then
        # Check pod conditions to understand why it's pending
        POD_SCHEDULED=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].status}' 2>/dev/null || echo "")
        
        if [ "$POD_SCHEDULED" == "False" ]; then
            CONTAINER_REASON="Scheduling"
            if [ "$SHOWN_SCHEDULING" == "false" ]; then
                REASON_MSG=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].message}' 2>/dev/null || echo "")
                if [ -n "$REASON_MSG" ]; then
                    echo -e "    ${YELLOW}Scheduling: $REASON_MSG${NC}"
                fi
                SHOWN_SCHEDULING=true
            fi
        elif [ "$POD_SCHEDULED" == "True" ]; then
            CONTAINER_REASON="Initializing"
        fi
    else
        # Check if container is waiting and get the reason
        if echo "$CONTAINER_STATE" | grep -q "waiting"; then
            CONTAINER_REASON=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")
            
            # Show image pull details once
            if [ "$CONTAINER_REASON" == "ContainerCreating" ] && [ "$SHOWN_PULLING" == "false" ]; then
                IMAGE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].image}' 2>/dev/null || echo "")
                echo "    Pulling image: $IMAGE"
                SHOWN_PULLING=true
            fi
        # Check if container is terminated and get the reason
        elif echo "$CONTAINER_STATE" | grep -q "terminated"; then
            CONTAINER_REASON=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}' 2>/dev/null || echo "")
        # Check if container is running
        elif echo "$CONTAINER_STATE" | grep -q "running"; then
            CONTAINER_REASON="Running"
        fi
    fi
    
    # Build status message
    STATUS_MSG="  Phase: $POD_PHASE"
    if [ -n "$CONTAINER_REASON" ]; then
        STATUS_MSG="$STATUS_MSG | Container: $CONTAINER_REASON"
    fi
    STATUS_MSG="$STATUS_MSG | Elapsed: ${ELAPSED}s"
    
    # Only print if message changed (reduce noise)
    if [ "$STATUS_MSG" != "$LAST_MESSAGE" ]; then
        echo "$STATUS_MSG"
        LAST_MESSAGE="$STATUS_MSG"
        
        # Show additional details for specific states
        if [ "$CONTAINER_REASON" == "ImagePullBackOff" ] || [ "$CONTAINER_REASON" == "ErrImagePull" ]; then
            echo -e "    ${RED}Image pull failed. Check events for details.${NC}"
        fi
    fi
    
    # Check for terminal states
    if [ "$POD_PHASE" == "Succeeded" ]; then
        echo -e "${GREEN}Pod completed successfully!${NC}"
        POD_STATUS="Succeeded"
        break
    elif [ "$POD_PHASE" == "Failed" ]; then
        echo -e "${RED}Pod failed!${NC}"
        POD_STATUS="Failed"
        break
    elif [ "$POD_PHASE" == "Unknown" ]; then
        echo -e "${RED}Pod status unknown!${NC}"
        POD_STATUS="Unknown"
        break
    fi
    
    sleep 3
done

echo ""
echo -e "${GREEN}=== Collecting Pod Information ===${NC}"

# Get pod describe output
echo "Collecting pod describe output..."
kubectl describe pod "$POD_NAME" -n "$NAMESPACE" > "$OUTPUT_DIR/pod-describe.txt" 2>&1 || echo "Failed to get pod describe" > "$OUTPUT_DIR/pod-describe.txt"

# Get pod logs
echo "Collecting pod logs..."
kubectl logs "$POD_NAME" -n "$NAMESPACE" > "$OUTPUT_DIR/pod-logs.txt" 2>&1 || echo "Failed to get pod logs" > "$OUTPUT_DIR/pod-logs.txt"

# Get pod YAML
echo "Collecting pod YAML..."
kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o yaml > "$OUTPUT_DIR/pod.yaml" 2>&1 || echo "Failed to get pod YAML" > "$OUTPUT_DIR/pod.yaml"

# Get pod events
echo "Collecting pod events..."
kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name="$POD_NAME" --sort-by='.lastTimestamp' > "$OUTPUT_DIR/pod-events.txt" 2>&1 || echo "Failed to get pod events" > "$OUTPUT_DIR/pod-events.txt"

# Create summary file
echo "Creating summary..."
cat > "$OUTPUT_DIR/summary.txt" <<EOF
GPU Simple Test Summary
========================
Pod Name: $POD_NAME
Namespace: $NAMESPACE
Timestamp: $(date)
Final Status: $POD_STATUS
Elapsed Time: ${ELAPSED}s

Pod Phase: $POD_PHASE
EOF

# Add container status to summary
echo "" >> "$OUTPUT_DIR/summary.txt"
echo "Container Status:" >> "$OUTPUT_DIR/summary.txt"
kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[*]}' >> "$OUTPUT_DIR/summary.txt" 2>&1 || echo "N/A" >> "$OUTPUT_DIR/summary.txt"
echo "" >> "$OUTPUT_DIR/summary.txt"

# Create archive
echo ""
echo -e "${GREEN}Creating archive: $ARCHIVE_NAME${NC}"
tar -czf "$ARCHIVE_NAME" "$OUTPUT_DIR"

echo -e "${GREEN}=== Results ===${NC}"
echo "Status: $POD_STATUS"
echo "Archive created: $ARCHIVE_NAME"
echo ""
echo "Contents:"
ls -lh "$OUTPUT_DIR"

# Display nvidia-smi output if successful
if [ "$POD_STATUS" == "Succeeded" ]; then
    echo ""
    echo -e "${GREEN}=== nvidia-smi Output ===${NC}"
    cat "$OUTPUT_DIR/pod-logs.txt"
fi

# Clean up directory (keep archive)
rm -rf "$OUTPUT_DIR"

echo ""
echo -e "${GREEN}=== Cleanup ===${NC}"
read -p "Do you want to delete the test pod? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Deleting pod..."
    kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --ignore-not-found=true
    echo -e "${GREEN}Pod deleted${NC}"
else
    echo -e "${YELLOW}Pod left running. Delete manually with: kubectl delete pod $POD_NAME -n $NAMESPACE${NC}"
fi

echo ""
echo -e "${GREEN}Done! Results saved in: $ARCHIVE_NAME${NC}"

# Cleanup temp YAML file
rm -f "$TEMP_YAML"

# Exit with appropriate code
if [ "$POD_STATUS" == "Succeeded" ]; then
    exit 0
else
    exit 1
fi

