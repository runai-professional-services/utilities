#!/bin/bash


green() {
  echo -e "\033[32m$1\033[0m"
}


function cleanup_cluster() {
  green "Cleaning up the Run:ai cluster..."

  green "Deleteing projects and workloads..."
  kubectl get projects | awk 'NR>1 {print $1}' | xargs kubectl delete projects $1
  kubectl get interactiveworkloads -A | awk 'NR>1 {print $1}' | xargs kubectl delete interactiveworkloads $1
  kubectl get trainingworkloads -A | awk 'NR>1 {print $1}' | xargs kubectl delete trainingworkloads $1

  green "Deleting the Run:ai configuration"
  kubectl delete runaiconfig runai -n runai

  green "Cleaning up any extra resources"
  kubectl get accessrules | awk 'NR>1 {print $1}' | xargs kubectl delete accessrules $1

  green "Performing helm delete on the runai-cluster"
  helm delete runai-cluster -n runai

  green "Deleting the runai namespace"
  kubectl delete ns runai

  green "Deleting the Run:ai cluster CRDs"
  kubectl get crd | grep run.ai | awk 'NR>1 {print $1}' | xargs kubectl delete crds $1
  kubectl get crd | grep run.ai | awk '{print $1}' | xargs kubectl delete crds $1
  kubectl get validatingwebhookconfiguration | grep runai | awk 'NR>1 {print $1}' | xargs kubectl delete validatingwebhookconfiguration $1
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
  kubectl get ns | grep runai | awk 'NR>1 {print $1}' |  xargs kubectl delete ns $1
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


