#!/bin/bash

set -e

check_command() {
  if [ $? -ne 0 ]; then
    echo "Error: $1 failed"
    exit 1
  fi
}

command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl is required but not installed. Aborting."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo >&2 "helm is required but not installed. Aborting."; exit 1; }

workloads=("interactiveworkloads.run.ai" "trainingworkloads.run.ai" "distributedworkloads.run.ai" "inferenceworkloads.run.ai" "externalworkloads.run.ai" "runaiconfig.run.ai")
resources=("project.run.ai" "accessrule.run.ai" "nodepools.run.ai")
TIMEOUT="30"

green() {
  echo -e "\033[32m$1\033[0m"
}

function remove_workloads() {
  for workload in "${workloads[@]}"; do
      echo "Processing: ${workload}"
      kubectl get ${workload} -A | awk 'NR>1 {print $1, $2}' | while read namespace resource_name; do
          kubectl -n "$namespace" patch ${workload} "$resource_name" -p '{"metadata":{"finalizers":[]}}' --type=merge
          check_command "kubectl patch ${workload} $resource_name"
          # Check if resource still exists after patching
          if kubectl -n "$namespace" get ${workload} "$resource_name" > /dev/null 2>&1; then
              kubectl -n "$namespace" delete ${workload} "$resource_name"
              check_command "kubectl delete ${workload} $resource_name"
          else
              echo "Resource ${resource_name} in namespace ${namespace} not found after patching, skipping delete."
          fi
      done
  done
}

function remove_resource_finalizer() {
  for resource in "${resources[@]}"; do
      echo "Processing: ${resource}"
      kubectl get ${resource} -A | awk 'NR>1 {print $1}' | xargs -r -I{} kubectl patch ${resource} {}  -p '{"metadata":{"finalizers":[]}}' --type=merge
      check_command "kubectl patch ${resource}"
  done
}

function cleanup_cluster() {
  green "Cleaning up the Run:ai cluster"

  green "Performing helm delete on the runai-cluster"
  if helm status runai-cluster -n runai > /dev/null 2>&1; then
    helm delete runai-cluster -n runai
    check_command "helm delete runai-cluster"
  else
    echo "Helm release runai-cluster not found, skipping delete."
  fi

  green "Deleting the validatingwebhookconfigurations..."
  kubectl get validatingwebhookconfiguration | grep runai | awk '{print $1}' | xargs -r -I{} kubectl delete validatingwebhookconfiguration {}
  check_command "kubectl delete validatingwebhookconfiguration"

  green "Deleting the mutatingwebhookconfiguration..."
  kubectl get mutatingwebhookconfiguration | grep runai | awk '{print $1}' | xargs -r -I{} kubectl delete mutatingwebhookconfiguration {}
  check_command "kubectl delete mutatingwebhookconfiguration"

  green "Deleting workloads..."
  remove_workloads

  green "Removing resource finalizers..."
  remove_resource_finalizer

  green "Deleting projects..."
  kubectl get projects.run.ai | awk 'NR>1 {print $1}' | xargs -r -I{} kubectl delete projects {}
  check_command "kubectl delete projects"

  green "Deleting the Run:ai configuration"
  if kubectl -n runai get runaiconfig runai > /dev/null 2>&1; then
    kubectl -n runai delete runaiconfig runai
    check_command "kubectl delete runaiconfig"
  else
    echo "Resource runaiconfig in namespace runai not found, skipping delete."
  fi
  check_command "kubectl delete runaiconfig"

  green "Deleting the runai namespace"
  kubectl delete ns runai --timeout=${TIMEOUT}s --ignore-not-found
  check_command "kubectl delete ns runai"

  green "Deleting the Run:ai cluster CRDs"
  kubectl get crd | grep run.ai | awk 'NR>1 {print $1}' | xargs -r -I{} kubectl delete crds {} --timeout=${TIMEOUT}s --ignore-not-found
  check_command "kubectl delete crds"

  kubectl get crd | grep run.ai | awk '{print $1}' | xargs -r -I{} kubectl delete crds {} --timeout=${TIMEOUT}s --ignore-not-found
  check_command "kubectl delete crds"
}

function cleanup_backend() {
  green "Performing helm delete on the runai-backend"
  helm delete runai-backend -n runai-backend
  check_command "helm delete runai-backend"

  green "Deleting the runai-backend PVCs"
  kubectl get pvc -n runai-backend | awk 'NR>1 {print $1}' | xargs -r -I{} kubectl -n runai-backend delete pvc {}
  check_command "kubectl delete pvc"

  green "Cleaning up any extra resources"
  kubectl -n runai-backend get job | awk 'NR>1 {print $1}' | xargs -r -I{} kubectl -n runai-backend delete job {}
  check_command "kubectl delete job"

  green "Deleting the runai-backend namespace"
  kubectl delete ns runai-backend
  check_command "kubectl delete ns runai-backend"

  green "Deleting all Run:ai related namespaces"
  kubectl get ns | grep runai | awk '{print $1}' |  xargs -r -I{} kubectl delete ns {}
  check_command "kubectl delete ns"
}

case "$1" in
  cluster)
    cleanup_cluster
    ;;
  backend)
    cleanup_backend
    ;;
  *)
    echo "Usage: $0 {cluster|backend}"
    exit 1
    ;;
esac
