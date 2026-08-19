#!/usr/bin/env bash
#
# delete_runai.sh — back up prerequisite secrets, then remove NVIDIA Run:ai
# components from a cluster.
#
# Runs in one of three modes:
#   all            control plane + cluster (default)
#   control-plane  the runai-backend release and namespace only
#   cluster        the runai-cluster release, its namespaces, and the
#                  cluster-scoped objects it owns (CRDs, webhooks, APIServices,
#                  priority classes)
#
# Order of operations:
#   0. Back up user-provided prerequisite secrets to YAML (ABORTS wipe on failure)
#   1. helm uninstall the in-scope releases, waiting for completion
#   2+ Remove what Helm leaves behind, scoped to the selected mode
#
# Safe to re-run (idempotent). Does NOT touch prerequisites (GPU operator,
# Prometheus, ingress, CSI drivers, etc.).
#
# Usage:
#   export KUBECONFIG=/path/to/kubeconfig
#   ./delete_runai.sh                     # everything
#   ./delete_runai.sh control-plane       # control plane only
#   ./delete_runai.sh cluster             # cluster only
#   DRY_RUN=1 ./delete_runai.sh cluster   # back up (read-only) + print the plan
#   ./delete_runai.sh --help

set -uo pipefail

usage() {
  cat <<'EOF'
Usage: delete_runai.sh [MODE]

Modes:
  all, everything          Remove the control plane and the cluster (default).
  control-plane, backend   Remove only the control plane: the runai-backend
                           Helm release and namespace. Cluster-scoped objects
                           (CRDs, webhooks, APIServices, priority classes) are
                           left alone because they belong to the cluster
                           component and removing them would break a cluster
                           that is still running.
  cluster                  Remove only the cluster: the runai-cluster Helm
                           release, the runai and runai-reservation namespaces,
                           and the cluster-scoped objects it owns.

Environment variables:
  DRY_RUN=1                  Print deletion commands without executing them.
  BACKUP_ALL=1               Back up all non-Helm, non-service-account secrets
                             in the in-scope namespaces.
  ASSUME_YES=1               Skip the interactive confirmation.
  DELETE_PROJECT_NAMESPACES=1
                             Also delete per-project namespaces (runai-<project>).
                             Ignored in control-plane mode.
  HELM_TIMEOUT=10m           Timeout used by helm uninstall.
  BACKUP_DIR=/path           Backup directory. Defaults to
                             ./runai-secrets-backup-YYYYMMDD-HHMMSS.
EOF
}

# ---- Mode --------------------------------------------------------------------
if [[ $# -gt 1 ]]; then
  echo "!! Too many arguments. Expected at most one mode." >&2
  usage >&2
  exit 2
fi

MODE="${1:-${MODE:-all}}"
case "$MODE" in
  -h|--help|help)                                   usage; exit 0 ;;
  all|everything)                                   MODE=all ;;
  control-plane|controlplane|ctrl-plane|cp|backend) MODE=control-plane ;;
  cluster)                                          MODE=cluster ;;
  *) echo "!! Unknown mode: $MODE" >&2; usage >&2; exit 2 ;;
esac

KUBECTL="kubectl --request-timeout=30s"
DRY="${DRY_RUN:-0}"
BACKUP_ALL="${BACKUP_ALL:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
DELETE_PROJECT_NS="${DELETE_PROJECT_NAMESPACES:-0}"
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"
BACKUP_DIR="${BACKUP_DIR:-./runai-secrets-backup-$(date +%Y%m%d-%H%M%S)}"

# ---- Preflight ---------------------------------------------------------------
# jq is used by the stuck-namespace sweep, where a failure would otherwise be
# swallowed by the trailing `|| true`.
MISSING_TOOLS=()
for tool in kubectl helm jq; do
  command -v "$tool" >/dev/null 2>&1 || MISSING_TOOLS+=("$tool")
done
if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
  echo "!! Required tool(s) not found in PATH: ${MISSING_TOOLS[*]}" >&2
  exit 1
fi

# ---- Per-component inventory -------------------------------------------------
# Secrets are prerequisite, user-provided ones, in "namespace/secretname" form.
CP_SECRETS=(
  "runai-backend/runai-reg-creds"
  "runai-backend/runai-backend-tls"
  "runai-backend/runai-ca-cert"
)
CLUSTER_SECRETS=(
  "runai/runai-reg-creds"
  "runai/runai-cluster-domain-tls-secret"
  "runai/runai-cluster-domain-star-tls-secret"
  "runai/runai-ca-cert"
  "knative-serving/runai-cluster-inference-tls-secret"
  "openshift-monitoring/runai-ca-cert"   # OpenShift only; skipped if absent
)

CP_HELM=(runai-backend:runai-backend)
CLUSTER_HELM=(runai-cluster:runai)

CP_NAMESPACES=(runai-backend)
CLUSTER_NAMESPACES=(runai runai-reservation)

# Every namespace Run:ai owns by a fixed name, in any mode. Used to keep
# project-namespace discovery from picking up an out-of-scope component.
ALL_KNOWN_NS=(runai runai-backend runai-reservation)

CRD_MATCH='run\.ai|resourceinterfaces\.optimization\.nvidia\.com'
PRIORITYCLASSES=(very-high high medium-high medium medium-low low very-low)

# ---- Scope the run to the selected mode --------------------------------------
# WIPE_CLUSTER_SCOPED covers CRDs, admission webhooks, APIServices and priority
# classes. These belong to the cluster component, so control-plane mode leaves
# them in place rather than breaking a cluster that is still running.
#
# RBAC is matched by name, and both components use a "runai" prefix, so the
# partial modes narrow the match to avoid deleting the other component's roles.
case "$MODE" in
  all)
    PREREQ_SECRETS=("${CP_SECRETS[@]}" "${CLUSTER_SECRETS[@]}")
    HELM_RELEASES=("${CLUSTER_HELM[@]}" "${CP_HELM[@]}")
    NAMESPACES=("${CLUSTER_NAMESPACES[@]}" "${CP_NAMESPACES[@]}")
    BACKUP_ALL_NS=(runai runai-backend knative-serving)
    WIPE_CLUSTER_SCOPED=1
    RBAC_INCLUDE='runai'
    RBAC_EXCLUDE=''
    ALLOW_PROJECT_NS=1
    ;;
  control-plane)
    PREREQ_SECRETS=("${CP_SECRETS[@]}")
    HELM_RELEASES=("${CP_HELM[@]}")
    NAMESPACES=("${CP_NAMESPACES[@]}")
    BACKUP_ALL_NS=(runai-backend)
    WIPE_CLUSTER_SCOPED=0
    RBAC_INCLUDE='runai-backend'
    RBAC_EXCLUDE=''
    ALLOW_PROJECT_NS=0
    ;;
  cluster)
    PREREQ_SECRETS=("${CLUSTER_SECRETS[@]}")
    HELM_RELEASES=("${CLUSTER_HELM[@]}")
    NAMESPACES=("${CLUSTER_NAMESPACES[@]}")
    BACKUP_ALL_NS=(runai knative-serving)
    WIPE_CLUSTER_SCOPED=1
    RBAC_INCLUDE='runai'
    RBAC_EXCLUDE='runai-backend'
    ALLOW_PROJECT_NS=1
    ;;
esac

if [[ "$DELETE_PROJECT_NS" == "1" && "$ALLOW_PROJECT_NS" == "0" ]]; then
  echo "!! DELETE_PROJECT_NAMESPACES=1 ignored in $MODE mode: per-project namespaces" >&2
  echo "   belong to the cluster component. Use \"cluster\" or \"all\" mode." >&2
fi

BACKUP_FAILED=0
SAVED=()      # "ns/name" successfully backed up
MISSING=()    # "ns/name" not present on the cluster (skipped)
FAILED=()     # "ns/name" present but backup failed

STEP=0

run() { if [[ "$DRY" == "1" ]]; then echo "  [dry-run] $*"; else eval "$*"; fi; }

step() { STEP=$((STEP + 1)); echo "==> $STEP. $*"; }

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

# Namespaces matching "runai" that Run:ai did not create under a fixed name —
# chiefly the per-project namespaces it creates as runai-<project>.
discover_extra_namespaces() {
  local ns known skip
  for ns in $($KUBECTL get ns -o name 2>/dev/null | sed 's|^namespace/||' | grep -i runai); do
    skip=0
    for known in "${ALL_KNOWN_NS[@]}"; do
      [[ "$ns" == "$known" ]] && { skip=1; break; }
    done
    [[ "$skip" == "0" ]] && echo "$ns"
  done
}

# Cluster-scoped RBAC in scope for this mode, as "kind/name" lines.
rbac_names() {
  local out
  out=$($KUBECTL get clusterrole,clusterrolebinding -o name 2>/dev/null | grep -Ei "$RBAC_INCLUDE") || return 0
  if [[ -n "$RBAC_EXCLUDE" ]]; then
    out=$(printf '%s\n' "$out" | grep -Eiv "$RBAC_EXCLUDE") || return 0
  fi
  printf '%s\n' "$out"
}

strip_finalizers() {
  local kind="$1"
  for obj in $($KUBECTL get "$kind" -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
    local ns="${obj%%|*}" name="${obj##*|}"
    local nsflag=""; [[ -n "$ns" ]] && nsflag="-n $ns"
    run "$KUBECTL patch $kind $name $nsflag --type=merge -p '{\"metadata\":{\"finalizers\":[]}}' >/dev/null 2>&1 || true"
  done
}

echo "==> Mode: $MODE"
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

# ---- Resolve which namespaces are in scope ----------------------------------
EXTRA_NS=()
if [[ "$ALLOW_PROJECT_NS" == "1" ]]; then
  while IFS= read -r _ns; do
    [[ -n "$_ns" ]] && EXTRA_NS+=("$_ns")
  done < <(discover_extra_namespaces)
fi

TARGET_NAMESPACES=("${NAMESPACES[@]}")
if [[ "$ALLOW_PROJECT_NS" == "1" && "$DELETE_PROJECT_NS" == "1" && ${#EXTRA_NS[@]} -gt 0 ]]; then
  TARGET_NAMESPACES+=("${EXTRA_NS[@]}")
fi

echo
echo "==================== DELETION PLAN ====================="
echo "Mode: $MODE"
echo "Helm releases (${#HELM_RELEASES[@]}):"
for entry in "${HELM_RELEASES[@]}"; do
  echo "    [delete] ${entry%%:*} (namespace ${entry##*:})"
done
echo "Namespaces (${#TARGET_NAMESPACES[@]}):"
printf '    [delete] %s\n' "${TARGET_NAMESPACES[@]}"
if [[ "$WIPE_CLUSTER_SCOPED" == "1" ]]; then
  echo "Cluster-scoped: CRDs, admission webhooks, APIServices, priority classes"
else
  echo "Cluster-scoped: SKIPPED — CRDs, webhooks, APIServices and priority classes"
  echo "                belong to the cluster component and are left in place."
fi
echo "Cluster RBAC:   names matching \"$RBAC_INCLUDE\"${RBAC_EXCLUDE:+, excluding \"$RBAC_EXCLUDE\"}"
if [[ ${#EXTRA_NS[@]} -gt 0 && "$DELETE_PROJECT_NS" != "1" ]]; then
  echo "Namespaces matching \"runai\" that will be LEFT IN PLACE (${#EXTRA_NS[@]}):"
  printf '    [keep]   %s\n' "${EXTRA_NS[@]}"
  echo "  These are typically per-project namespaces holding user workloads and data."
  echo "  Re-run with DELETE_PROJECT_NAMESPACES=1 to delete them too."
fi
echo "========================================================"

# ---- Confirmation gate ------------------------------------------------------
if [[ "$DRY" == "1" ]]; then
  echo
  echo "(dry-run) Skipping confirmation. The steps below show what WOULD run:"
elif [[ "$ASSUME_YES" == "1" ]]; then
  echo
  echo "ASSUME_YES=1 set — proceeding with the wipe without prompting."
else
  echo
  read -r -p "Proceed to WIPE Run:ai (mode: $MODE)? Type 'y' to continue [y/N] " _ans </dev/tty || _ans=""
  case "$_ans" in
    [yY]|[yY][eE][sS]) echo "Confirmed — proceeding with the wipe." ;;
    *) echo "Aborted by user. No changes made. Secrets remain saved in $BACKUP_DIR"; exit 0 ;;
  esac
fi

step "Uninstalling Run:ai Helm releases (waiting for completion)"
for entry in "${HELM_RELEASES[@]}"; do
  rel="${entry%%:*}" ns="${entry##*:}"
  if helm status "$rel" -n "$ns" >/dev/null 2>&1; then
    echo "  - helm uninstall $rel -n $ns"
    run "helm uninstall $rel -n $ns --wait --timeout $HELM_TIMEOUT --debug"
  else
    echo "  - $rel (ns $ns): no such release, skipping"
  fi
done

if [[ "$WIPE_CLUSTER_SCOPED" == "1" ]]; then
  step "Deleting Run:ai admission webhooks"
  for hook in validatingwebhookconfiguration mutatingwebhookconfiguration; do
    for w in $($KUBECTL get "$hook" -o name 2>/dev/null | grep -i runai); do
      run "$KUBECTL delete $w --wait=false --ignore-not-found"
    done
  done

  step "Deleting Run:ai APIServices"
  for a in $($KUBECTL get apiservice -o name 2>/dev/null | grep -Ei 'run\.ai'); do
    run "$KUBECTL delete $a --wait=false --ignore-not-found"
  done

  step "Clearing finalizers on all Run:ai custom resources"
  for crd in $($KUBECTL get crd -o name 2>/dev/null | grep -Ei "$CRD_MATCH" | sed 's|customresourcedefinition.apiextensions.k8s.io/||'); do
    strip_finalizers "$crd"
  done

  step "Deleting Run:ai CRDs (cascades their custom resources)"
  for c in $($KUBECTL get crd -o name 2>/dev/null | grep -Ei "$CRD_MATCH"); do
    run "$KUBECTL delete $c --wait=false --ignore-not-found"
  done
fi

step "Deleting Run:ai ClusterRoles / ClusterRoleBindings"
for rb in $(rbac_names); do
  run "$KUBECTL delete $rb --wait=false --ignore-not-found"
done

if [[ "$WIPE_CLUSTER_SCOPED" == "1" ]]; then
  step "Deleting Run:ai PriorityClasses"
  for pc in "${PRIORITYCLASSES[@]}"; do
    run "$KUBECTL delete priorityclass $pc --wait=false --ignore-not-found"
  done
fi

# Deleting PVCs explicitly, rather than relying on the namespace cascade, so the
# PV reclaim policy still fires if the sweep below has to force-clear a
# namespace finalizer — that path would otherwise orphan the PVCs and strand
# their PVs.
step "Deleting PersistentVolumeClaims in target namespaces"
for ns in "${TARGET_NAMESPACES[@]}"; do
  $KUBECTL get ns "$ns" >/dev/null 2>&1 || continue
  for pvc in $($KUBECTL get pvc -n "$ns" -o name 2>/dev/null); do
    run "$KUBECTL delete $pvc -n $ns --wait=false --ignore-not-found"
  done
done

step "Deleting Run:ai namespaces"
for ns in "${TARGET_NAMESPACES[@]}"; do
  run "$KUBECTL delete namespace $ns --wait=false --ignore-not-found"
done

step "Sweeping any namespaces stuck in Terminating (orphaned finalizers)"
sleep 5
for ns in "${TARGET_NAMESPACES[@]}"; do
  if $KUBECTL get ns "$ns" >/dev/null 2>&1; then
    run "$KUBECTL get ns $ns -o json | jq 'del(.spec.finalizers)' | $KUBECTL replace --raw \"/api/v1/namespaces/$ns/finalize\" -f - >/dev/null 2>&1 || true"
  fi
done

# ---- Verification -----------------------------------------------------------
# Counts are scoped to what this mode was supposed to remove, so a non-zero
# figure always means something was left behind.
echo
echo "==> Verification (mode: $MODE)"

_helm_left=0
for entry in "${HELM_RELEASES[@]}"; do
  helm status "${entry%%:*}" -n "${entry##*:}" >/dev/null 2>&1 && _helm_left=$((_helm_left + 1))
done
printf '  Helm releases:    %s\n' "$_helm_left"

_ns_left=0
for ns in "${TARGET_NAMESPACES[@]}"; do
  $KUBECTL get ns "$ns" >/dev/null 2>&1 && _ns_left=$((_ns_left + 1))
done
printf '  Namespaces:       %s\n' "$_ns_left"

if [[ "$WIPE_CLUSTER_SCOPED" == "1" ]]; then
  printf '  CRDs:             %s\n' "$($KUBECTL get crd -o name 2>/dev/null | grep -Eic "$CRD_MATCH")"
  printf '  Validating hooks: %s\n' "$($KUBECTL get validatingwebhookconfiguration -o name 2>/dev/null | grep -ic runai)"
  printf '  Mutating hooks:   %s\n' "$($KUBECTL get mutatingwebhookconfiguration -o name 2>/dev/null | grep -ic runai)"
  printf '  APIServices:      %s\n' "$($KUBECTL get apiservice -o name 2>/dev/null | grep -Eic 'run\.ai')"
fi

printf '  ClusterRoles:     %s\n' "$(rbac_names | grep -c . )"

_ns_re=$(printf '%s|' "${TARGET_NAMESPACES[@]}"); _ns_re="^(${_ns_re%|})$"
printf '  Stranded PVs:     %s\n' "$($KUBECTL get pv -o jsonpath='{range .items[*]}{.spec.claimRef.namespace}{"\n"}{end}' 2>/dev/null | grep -Ec "$_ns_re")"

if [[ ${#EXTRA_NS[@]} -gt 0 && "$DELETE_PROJECT_NS" != "1" ]]; then
  echo "  Note: ${#EXTRA_NS[@]} namespace(s) matching \"runai\" were deliberately kept:"
  printf '        %s\n' "${EXTRA_NS[@]}"
fi
if [[ "$WIPE_CLUSTER_SCOPED" != "1" ]]; then
  echo "  Note: CRDs, webhooks, APIServices and priority classes were not touched."
  echo "        Run \"$0 cluster\" or \"$0 all\" to remove them."
fi
echo "==> Done. Secrets backed up in: $BACKUP_DIR"
