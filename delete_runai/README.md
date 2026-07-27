# Delete Run:ai

`delete_runai.sh` backs up selected Kubernetes secrets and then removes Run:ai
from a cluster. It is designed to be safe to re-run and does not remove common
prerequisites such as the NVIDIA GPU Operator, Prometheus, ingress controllers,
or CSI drivers.

> **Warning:** This is a destructive, cluster-wide operation. Confirm that
> `kubectl` and `helm` target the intended cluster before running it.

## Prerequisites

- Bash
- `kubectl`
- `helm`
- `jq`
- `grep` and `sed`
- A kubeconfig with permission to read secrets and delete cluster-scoped and
  namespace-scoped resources

Check the current context before proceeding:

```bash
kubectl config current-context
kubectl cluster-info
```

## Usage

From this directory:

```bash
chmod +x delete_runai.sh
export KUBECONFIG=/path/to/kubeconfig
./delete_runai.sh
```

The script asks for confirmation before deleting anything. Enter `y` or `yes`
to continue.

Start with a dry run to inspect the planned deletion commands:

```bash
DRY_RUN=1 ./delete_runai.sh
```

Dry-run mode still reads and writes the secret backups, but it does not run the
deletion commands.

## Configuration

The script accepts the following environment variables:

- `DRY_RUN=1`: Print deletion commands without executing them.
- `BACKUP_ALL=1`: Back up all non-Helm, non-service-account secrets in the
  `runai`, `runai-backend`, and `knative-serving` namespaces.
- `ASSUME_YES=1`: Skip the interactive deletion confirmation. Use this only in
  controlled automation.
- `HELM_TIMEOUT=10m`: Set the timeout used by `helm uninstall`.
- `BACKUP_DIR=/path`: Choose the backup directory. By default, backups are
  written to `./runai-secrets-backup-YYYYMMDD-HHMMSS`.

For example:

```bash
BACKUP_ALL=1 \
BACKUP_DIR="$HOME/runai-backup" \
HELM_TIMEOUT=20m \
./delete_runai.sh
```

## What the script does

1. Backs up known prerequisite secrets as re-applicable YAML.
2. Aborts before deletion if an existing prerequisite secret cannot be backed
   up.
3. Uninstalls the `runai-cluster` and `runai-backend` Helm releases.
4. Deletes Run:ai admission webhooks.
5. Clears finalizers from Run:ai custom resources.
6. Deletes matching Run:ai and NVIDIA resource-interface CRDs.
7. Deletes matching cluster roles and cluster role bindings.
8. Deletes the Run:ai priority classes.
9. Deletes the `runai`, `runai-backend`, and `runai-reservation` namespaces.
10. Clears finalizers from those namespaces if they remain in `Terminating`.
11. Prints counts of remaining Run:ai resources for verification.

Most deletions use name-based matching, so review the script before using it on
a shared cluster.

## Secret backups

Backups contain Kubernetes secret data and must be treated as sensitive. Store
the directory securely, restrict access to it, and remove it when it is no
longer needed.

Restore saved secrets with:

```bash
kubectl apply -f /path/to/runai-secrets-backup/
```

Restoring secrets does not reinstall Run:ai. Follow the appropriate Run:ai
installation procedure after restoring any required prerequisites.

## Verification

The script prints a verification summary when it finishes. You can also check
manually:

```bash
helm list -A | grep -i runai
kubectl get crd | grep -Ei 'run\.ai|resourceinterfaces\.optimization\.nvidia\.com'
kubectl get namespace | grep -i runai
kubectl get validatingwebhookconfiguration,mutatingwebhookconfiguration \
  -o name | grep -i runai
kubectl get clusterrole,clusterrolebinding -o name | grep -i runai
```

Commands that produce no output indicate that no matching resources remain.
