#!/bin/bash

set -euo pipefail

# Script to detect and fix RunAI policies missing scope labels
# Usage:
#   ./start.sh --dry-run    # Only detect issues (default)
#   ./start.sh --fix        # Detect and fix issues

MODE="dry-run"
if [[ "${1:-}" == "--fix" ]]; then
    MODE="fix"
elif [[ "${1:-}" == "--dry-run" || "${1:-}" == "" ]]; then
    MODE="dry-run"
else
    echo "Usage: $0 [--dry-run|--fix]"
    echo "  --dry-run  : Only detect and report issues (default)"
    echo "  --fix      : Detect and automatically fix missing scope labels"
    exit 1
fi

echo "=========================================================================="
if [[ "$MODE" == "fix" ]]; then
    echo "RunAI Policy Scope Label Fixer (FIX MODE)"
else
    echo "RunAI Policy Scope Label Audit (DRY-RUN MODE)"
fi
echo "=========================================================================="

# Function to get project ID from namespace
get_project_id_from_namespace() {
    local namespace="$1"
    # Get the project name from the runai/queue label
    local project_name=$(kubectl get namespace "$namespace" -o jsonpath='{.metadata.labels.runai/queue}' 2>/dev/null || echo "")
    if [[ -z "$project_name" ]]; then
        echo ""
        return
    fi
    
    # Get the project ID from the project resource
    local project_id=$(kubectl get project "$project_name" -o jsonpath='{.metadata.labels.runai/project-id}' 2>/dev/null || echo "")
    echo "$project_id"
}

# Function to get department ID from namespace
get_department_id_from_namespace() {
    local namespace="$1"
    # Get the project name from the runai/queue label
    local project_name=$(kubectl get namespace "$namespace" -o jsonpath='{.metadata.labels.runai/queue}' 2>/dev/null || echo "")
    if [[ -z "$project_name" ]]; then
        echo ""
        return
    fi
    
    # Get the department ID from the project resource
    local department_id=$(kubectl get project "$project_name" -o jsonpath='{.metadata.labels.run\.ai/department-id}' 2>/dev/null || echo "")
    echo "$department_id"
}

# Function to fix policy scope labels
fix_policy_scope() {
    local policy_type="$1"
    local policy_name="$2"
    local namespace="$3"
    
    echo "🔧 Fixing $policy_type/$policy_name in namespace $namespace..."
    
    # Determine the scope based on namespace location
    if [[ "$namespace" == "runai" ]]; then
        # Policies in runai namespace are typically cluster or department scoped
        # Check if this is a cluster-wide policy by looking for cluster indicator
        # For now, we'll assume project scope since most policies are project-scoped
        echo "   Policy is in 'runai' namespace - checking scope..."
        
        # Get department ID - if available, use department scope
        local department_id=$(get_department_id_from_namespace "$namespace")
        if [[ -n "$department_id" ]]; then
            echo "   Setting department scope with ID: $department_id"
            if [[ "$MODE" == "fix" ]]; then
                kubectl patch "$policy_type" "$policy_name" -n "$namespace" \
                    --type='merge' \
                    -p='{"metadata":{"labels":{"run.ai/department":"'$department_id'"}}}' || {
                    echo "   ❌ Failed to patch $policy_type/$policy_name with department scope"
                    return 1
                }
                echo "   ✅ Successfully added department scope label"
            fi
        else
            # Default to cluster scope for policies in runai namespace
            echo "   Setting cluster scope"
            if [[ "$MODE" == "fix" ]]; then
                kubectl patch "$policy_type" "$policy_name" -n "$namespace" \
                    --type='merge' \
                    -p='{"metadata":{"labels":{"run.ai/cluster-wide":"true"}}}' || {
                    echo "   ❌ Failed to patch $policy_type/$policy_name with cluster scope"
                    return 1
                }
                echo "   ✅ Successfully added cluster scope label"
            fi
        fi
    else
        # Policies in project namespaces should get project scope
        local project_id=$(get_project_id_from_namespace "$namespace")
        if [[ -n "$project_id" ]]; then
            echo "   Setting project scope with ID: $project_id"
            if [[ "$MODE" == "fix" ]]; then
                kubectl patch "$policy_type" "$policy_name" -n "$namespace" \
                    --type='merge' \
                    -p='{"metadata":{"labels":{"run.ai/project":"'$project_id'"}}}' || {
                    echo "   ❌ Failed to patch $policy_type/$policy_name with project scope"
                    return 1
                }
                echo "   ✅ Successfully added project scope label"
            fi
        else
            echo "   ❌ Cannot determine project ID for namespace $namespace"
            return 1
        fi
    fi
    
    return 0
}

NAMESPACES=$(kubectl get namespaces -l runai/queue --no-headers -o custom-columns="NAME:.metadata.name")

echo "Found RunAI namespaces:"
echo "$NAMESPACES"
echo ""

TOTAL_POLICIES=0
MISSING_SCOPE=0
HAS_SCOPE=0
FIXED_POLICIES=0
FAILED_FIXES=0

for ns in $NAMESPACES; do
    echo "=== Namespace: $ns ==="
    
    # Get policies with their current scope labels
    output=$(kubectl get inferencepolicy,trainingpolicy,interactivepolicy,distributedpolicy -n $ns \
        -o custom-columns="TYPE:.kind,NAME:.metadata.name,NAMESPACE:.metadata.namespace,PROJECT:.metadata.labels.run\.ai/project,DEPARTMENT:.metadata.labels.run\.ai/department,CLUSTER:.metadata.labels.run\.ai/cluster-wide,TENANT:.metadata.labels.run\.ai/tenant-wide" \
        --no-headers 2>/dev/null || echo "")
    
    if [[ -z "$output" ]]; then
        echo "No policies found"
        continue
    fi
    
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        # Parse: TYPE NAME NAMESPACE PROJECT DEPARTMENT CLUSTER TENANT
        read -r type name namespace project department cluster tenant <<< "$line"
        
        TOTAL_POLICIES=$((TOTAL_POLICIES + 1))
        
        if [[ "$project" == "<none>" && "$department" == "<none>" && "$cluster" == "<none>" && "$tenant" == "<none>" ]]; then
            echo "❌ $type/$name: MISSING_ALL_SCOPE_LABELS"
            MISSING_SCOPE=$((MISSING_SCOPE + 1))
            
            # Attempt to fix if in fix mode
            if [[ "$MODE" == "fix" ]]; then
                if fix_policy_scope "$type" "$name" "$namespace"; then
                    FIXED_POLICIES=$((FIXED_POLICIES + 1))
                else
                    FAILED_FIXES=$((FAILED_FIXES + 1))
                fi
            fi
        else
            # Show which labels are present
            scope_info=""
            [[ "$project" != "<none>" ]] && scope_info+="project=$project "
            [[ "$department" != "<none>" ]] && scope_info+="department=$department "
            [[ "$cluster" != "<none>" ]] && scope_info+="cluster=$cluster "
            [[ "$tenant" != "<none>" ]] && scope_info+="tenant=$tenant "
            
            echo "✅ $type/$name: HAS_SCOPE_LABELS → $scope_info"
            HAS_SCOPE=$((HAS_SCOPE + 1))
        fi
        
    done <<< "$output"
    echo ""
done

echo "=========================================================================="
if [[ "$MODE" == "fix" ]]; then
    echo "FIX RESULTS"
else
    echo "AUDIT RESULTS"
fi
echo "=========================================================================="
echo "Total policies: $TOTAL_POLICIES"
echo "Policies with scope labels: $HAS_SCOPE"
echo "Policies missing scope labels: $MISSING_SCOPE"

if [[ "$MODE" == "fix" && $MISSING_SCOPE -gt 0 ]]; then
    echo ""
    echo "Fix Results:"
    echo "✅ Successfully fixed: $FIXED_POLICIES"
    echo "❌ Failed to fix: $FAILED_FIXES"
fi

echo ""

if [[ $MISSING_SCOPE -eq 0 ]]; then
    echo "✅ SUCCESS: All policies have proper scope labels!"
    echo ""
    echo "📋 CONCLUSION:"
    echo "   - No 'Unable to identify relevant scope' errors expected from policies"
    echo "   - The cluster-sync issues may have a different root cause"
elif [[ "$MODE" == "dry-run" ]]; then
    echo "❌ FOUND ISSUES: $MISSING_SCOPE policies are missing scope labels"
    echo ""
    echo "📋 NEXT STEPS:"
    echo "   - Run this script with --fix to automatically add missing labels:"
    echo "     $0 --fix"
elif [[ "$MODE" == "fix" ]]; then
    if [[ $FAILED_FIXES -eq 0 ]]; then
        echo "✅ All scope label issues have been fixed!"
    else
        echo "⚠️  Some issues remain: $FAILED_FIXES policies could not be fixed"
        echo "   Please review the error messages above and fix manually"
    fi
fi

echo ""
echo "=========================================================================="
