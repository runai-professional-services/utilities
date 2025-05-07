#!/bin/bash


workloads=("interactiveworkloads" "trainingworkloads" "distributedworkloads" "inferenceworkloads" "externalworkloads")
resources=("project" "accessrule" "nodepools" "runaiconfig")
TIMEOUT="30"


green() {
  echo -e "\033[32m$1\033[0m"
}

function remove_workload_finalizer() {
  for workload in "${workloads[@]}"; do
      echo "Processing: ${workload}"
      kubectl get ${workload} -A | awk 'NR>1 {print $1, $2}' | while read namespace resource_name; do
          kubectl -n "$namespace" patch ${workload} "$resource_name" -p '{"metadata":{"finalizers":[]}}' --type=merge
      done
  done
}


function remove_resource_finalizer() {
  for resource in "${resources[@]}"; do
      echo "Processing: ${resource}"
      kubectl get ${resource} -A | awk 'NR>1 {print $1}' | xargs kubectl patch $1 ${resource} -p '{"metadata":{"finalizers":[]}}' --type=merge
  done
}


function cleanup_cluster() {
  green "Cleaning up the Run:ai cluster"

  green "Performing helm delete on the runai-cluster"
  kubectl delete runai-cluster -n runai

  green "Deleting the validatingwebhookconfigurations..."
  kubectl get validatingwebhookconfiguration | grep runai | awk '{print $1}' | xargs kubectl delete validatingwebhookconfiguration $1
  kubectl get mutatingwebhookconfiguration | grep runai | awk '{print $1}' | xargs kubectl delete mutatingwebhookconfiguration $1

  green "Removing workload finalizers..."
  remove_workload_finalizer

  green "Removing resource finalizers..."
  remove_resource_finalizer

  green "Deleteing projects and workloads..."
  kubectl get projects | awk 'NR>1 {print $1}' | xargs kubectl delete projects $1
  kubectl get interactiveworkloads -A | awk 'NR>1 {print $1}' | xargs kubectl delete interactiveworkloads $1
  kubectl get trainingworkloads -A | awk 'NR>1 {print $1}' | xargs kubectl delete trainingworkloads $1
  kubectl get distributedworkloads -A | awk 'NR>1 {print $1}' | xargs kubectl delete distributedworkloads $1
  kubectl get inferenceworkloads -A | awk 'NR>1 {print $1}' | xargs kubectl delete inferenceworkloads $1


  green "Deleting the Run:ai configuration"
  kubectl delete runaiconfig runai -n runai

  green "Cleaning up any extra resources"

  green "Deleting the runai namespace"
  kubectl delete ns runai

  green "Deleting the Run:ai cluster CRDs"
  kubectl get crd | grep run.ai | awk 'NR>1 {print $1}' | xargs kubectl delete crds $1 --timeout=${TIMEOUT}s --ignore-not-found
  kubectl get crd | grep run.ai | awk '{print $1}' | xargs kubectl delete crds $1 --timeout=${TIMEOUT}s --ignore-not-found
}


function cleanup_backend() {
  green "Performing helm delete on the runai-backend"
  helm delete runai-backend -n runai-backend

  green "Deleting the runai-backend PVCs"
  kubectl get pvc -n runai-backend | awk 'NR>1 {print $1}' | xargs kubectl -n runai-backend delete pvc $1

  green "Cleaning up any extra resources"
  kubectl -n runai-backend get job | awk 'NR>1 {print $1}' | xargs kubectl -n runai-backend delete job $1

  green "Deleting the runai-backend namespace"
  kubectl delete ns runai-backend

  green "Deleting all Run:ai related namespaces"
  kubectl get ns | grep runai | awk '{print $1}' |  xargs kubectl delete ns $1
}


# Check if the first argument is cluster
if [ "$1" == "cluster" ]; then
  cleanup_cluster
else
  echo "Usage: ./cleanup.sh cluster"
fi


# Check if the first argument is backend
if [ "$1" == "backend" ]; then
  cleanup_backend
else
  echo "Usage: ./cleanup.sh backend"
fi
