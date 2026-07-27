#!/usr/bin/env bash
#
# wipe-runai.sh — back up prerequisite secrets, then completely remove all
# NVIDIA Run:ai components from a cluster.
#
# Order of operations:
#   0. Back up user-provided prerequisite secrets to YAML (ABORTS wipe on failure)
#   1. helm uninstall (control plane + cluster), waiting for completion
#   2..8. Remove everything Helm leaves behind (CRs, CRDs, webhooks, RBAC,
#         priority classes, namespaces)
#
# Safe to re-run (idempotent). Does NOT touch prerequisites (GPU operator,
# Prometheus, ingress, CSI drivers, etc.).
#
# Usage:
#   export KUBECONFIG=/path/to/kubeconfig
#   ./wipe-runai.sh              # back up, then wipe
#   DRY_RUN=1 ./wipe-runai.sh    # back up (read-only) + print what would be deleted
#   BACKUP_ALL=1 ./wipe-runai.sh # also dump every non-helm/non-SA secret in the runai namespaces
#   ASSUME_YES=1 ./wipe-runai.sh # skip the interactive "proceed to wipe?" confirmation

set -uo pipefail

KUBECTL="kubectl --request-timeout=30s"
DRY="${DRY_RUN:-0}"
BACKUP_ALL="${BACKUP_ALL:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"
BACKUP_DIR="${BACKUP_DIR:-./runai-secrets-backup-$(date +%Y%m%d-%H%M%S)}"

# ---- What to back up (prerequisite, user-provided secrets) -------------------
# Format: "namespace/secretname"
PREREQ_SECRETS=(
  "runai-backend/runai-reg-creds"
  "runai-backend/runai-backend-tls"
  "runai-backend/runai-ca-cert"
  "runai/runai-reg-creds"
  "runai/runai-cluster-domain-tls-secret"
  "runai/runai-cluster-domain-star-tls-secret"
  "runai/runai-ca-cert"
  "knative-serving/runai-cluster-inference-tls-secret"
  "openshift-monitoring/runai-ca-cert"   # OpenShift only; skipped if absent
)
# Namespaces to scan when BACKUP_ALL=1
BACKUP_ALL_NS=(runai runai-backend knative-serving)

# ---- What to wipe ------------------------------------------------------------
HELM_RELEASES=(runai-cluster:runai runai-backend:runai-backend)
CRD_MATCH='run\.ai|resourceinterfaces\.optimization\.nvidia\.com'
NAMESPACES=(runai runai-backend runai-reservation)
PRIORITYCLASSES=(very-high high medium-high medium medium-low low very-low)

BACKUP_FAILED=0
SAVED=()      # "ns/name" successfully backed up
MISSING=()    # "ns/name" not present on the cluster (skipped)
FAILED=()     # "ns/name" present but backup failed

run() { if [[ "$DRY" == "1" ]]; then echo "  [dry-run] $*"; else eval "$*"; fi; }

# Dump a secret as clean, re-appliable YAML. Read-only; always runs.
backup_secret() {
  local ns="$1" name="$2"
  $KUBECTL get secret "$name" -n "$ns" >/dev/null 2>&1 || { echo "  - skip $ns/$name (not found)"; MISSING+=("$ns/$name"); return; }
  local f="$BACKUP_DIR/${ns}__${name}.yaml"
  mkdir -p "$BACKUP_DIR"
  if $KUBECTL get secret "$name" -n "$ns" -o yaml 2>/dev/null \
       | grep -vE '^\s+(resourceVersion|uid|creationTimestamp|generation|selfLink):' \
       | grep -vE '^\s+kubectl\.kubernetes\.io/last-applied-configuration:' \
       > "$f" && [[ -s "$f" ]]; then
    echo "  - saved $ns/$name -> $f"
    SAVED+=("$ns/$name")
  else
    echo "  !! FAILED to back up $ns/$name" >&2
    FAILED+=("$ns/$name")
    BACKUP_FAILED=1
  fi
}

strip_finalizers() {
  local kind="$1"
  for obj in $($KUBECTL get "$kind" -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
    local ns="${obj%%|*}" name="${obj##*|}"
    local nsflag=""; [[ -n "$ns" ]] && nsflag="-n $ns"
    run "$KUBECTL patch $kind $name $nsflag --type=merge -p '{\"metadata\":{\"finalizers\":[]}}' >/dev/null 2>&1 || true"
  done
}

echo "==> 0. Backing up prerequisite secrets to $BACKUP_DIR"
for entry in "${PREREQ_SECRETS[@]}"; do
  backup_secret "${entry%%/*}" "${entry##*/}"
done
if [[ "$BACKUP_ALL" == "1" ]]; then
  echo "  (BACKUP_ALL) dumping all non-helm / non-service-account secrets"
  for ns in "${BACKUP_ALL_NS[@]}"; do
    for s in $($KUBECTL get secret -n "$ns" -o jsonpath='{range .items[?(@.type!="kubernetes.io/service-account-token")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -v '^sh.helm.release'); do
      backup_secret "$ns" "$s"
    done
  done
fi
# ---- Backup summary ---------------------------------------------------------
echo
echo "==================== BACKUP SUMMARY ===================="
echo "Saved (${#SAVED[@]}):"
if [[ ${#SAVED[@]} -eq 0 ]]; then echo "    (none)"; else printf '    [saved]  %s\n' "${SAVED[@]}"; fi
echo "Not found / skipped (${#MISSING[@]}):"
if [[ ${#MISSING[@]} -eq 0 ]]; then echo "    (none)"; else printf '    [absent] %s\n' "${MISSING[@]}"; fi
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "FAILED (${#FAILED[@]}):"
  printf '    [FAIL]   %s\n' "${FAILED[@]}"
fi
echo "Backup directory: $BACKUP_DIR"
echo "========================================================"

if [[ "$BACKUP_FAILED" == "1" ]]; then
  echo "!! One or more existing secrets failed to back up. ABORTING before any wipe." >&2
  exit 1
fi
if [[ ${#SAVED[@]} -gt 0 ]]; then
  echo "Restore later with: kubectl apply -f $BACKUP_DIR/"
fi

# ---- Confirmation gate ------------------------------------------------------
if [[ "$DRY" == "1" ]]; then
  echo
  echo "(dry-run) Skipping confirmation. The steps below show what WOULD run:"
elif [[ "$ASSUME_YES" == "1" ]]; then
  echo
  echo "ASSUME_YES=1 set — proceeding with the wipe without prompting."
else
  echo
  read -r -p "Proceed to WIPE all Run:ai components? Type 'y' to continue [y/N] " _ans </dev/tty || _ans=""
  case "$_ans" in
    [yY]|[yY][eE][sS]) echo "Confirmed — proceeding with the wipe." ;;
    *) echo "Aborted by user. No changes made. Secrets remain saved in $BACKUP_DIR"; exit 0 ;;
  esac
fi

echo "==> 1. Uninstalling Run:ai Helm releases (waiting for completion)"
for entry in "${HELM_RELEASES[@]}"; do
  rel="${entry%%:*}" ns="${entry##*:}"
  if helm status "$rel" -n "$ns" >/dev/null 2>&1; then
    echo "  - helm uninstall $rel -n $ns"
    run "helm uninstall $rel -n $ns --wait --timeout $HELM_TIMEOUT --debug"
  else
    echo "  - $rel (ns $ns): no such release, skipping"
  fi
done

echo "==> 2. Deleting Run:ai admission webhooks"
for hook in validatingwebhookconfiguration mutatingwebhookconfiguration; do
  for w in $($KUBECTL get "$hook" -o name 2>/dev/null | grep -i runai); do
    run "$KUBECTL delete $w --wait=false --ignore-not-found"
  done
done

echo "==> 3. Clearing finalizers on all Run:ai custom resources"
for crd in $($KUBECTL get crd -o name 2>/dev/null | grep -Ei "$CRD_MATCH" | sed 's|customresourcedefinition.apiextensions.k8s.io/||'); do
  strip_finalizers "$crd"
done

echo "==> 4. Deleting Run:ai CRDs (cascades their custom resources)"
for c in $($KUBECTL get crd -o name 2>/dev/null | grep -Ei "$CRD_MATCH"); do
  run "$KUBECTL delete $c --wait=false --ignore-not-found"
done

echo "==> 5. Deleting Run:ai ClusterRoles / ClusterRoleBindings"
for rb in $($KUBECTL get clusterrole,clusterrolebinding -o name 2>/dev/null | grep -i runai); do
  run "$KUBECTL delete $rb --wait=false --ignore-not-found"
done

echo "==> 6. Deleting Run:ai PriorityClasses"
for pc in "${PRIORITYCLASSES[@]}"; do
  run "$KUBECTL delete priorityclass $pc --wait=false --ignore-not-found"
done

echo "==> 7. Deleting Run:ai namespaces"
for ns in "${NAMESPACES[@]}"; do
  run "$KUBECTL delete namespace $ns --wait=false --ignore-not-found"
done

echo "==> 8. Sweeping any namespaces stuck in Terminating (orphaned finalizers)"
sleep 5
for ns in "${NAMESPACES[@]}"; do
  if $KUBECTL get ns "$ns" >/dev/null 2>&1; then
    run "$KUBECTL get ns $ns -o json | jq 'del(.spec.finalizers)' | $KUBECTL replace --raw \"/api/v1/namespaces/$ns/finalize\" -f - >/dev/null 2>&1 || true"
  fi
done

echo
echo "==> Verification"
printf '  Helm releases:   %s\n' "$(helm list -A 2>/dev/null | grep -ic runai)"
printf '  CRDs:            %s\n' "$($KUBECTL get crd -o name 2>/dev/null | grep -Eic "$CRD_MATCH")"
printf '  Namespaces:      %s\n' "$($KUBECTL get ns -o name 2>/dev/null | grep -ic runai)"
printf '  Validating hooks:%s\n' "$($KUBECTL get validatingwebhookconfiguration -o name 2>/dev/null | grep -ic runai)"
printf '  Mutating hooks:  %s\n' "$($KUBECTL get mutatingwebhookconfiguration -o name 2>/dev/null | grep -ic runai)"
printf '  APIServices:     %s\n' "$($KUBECTL get apiservice -o name 2>/dev/null | grep -Eic 'run\.ai')"
printf '  ClusterRoles:    %s\n' "$($KUBECTL get clusterrole,clusterrolebinding -o name 2>/dev/null | grep -ic runai)"
echo "==> Done. Secrets backed up in: $BACKUP_DIR"