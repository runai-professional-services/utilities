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
./delete_runai.sh [MODE]
```

The script asks for confirmation before deleting anything. Enter `y` or `yes`
to continue.

Start with a dry run to inspect the planned deletion commands:

```bash
DRY_RUN=1 ./delete_runai.sh
```

Dry-run mode still reads and writes the secret backups, but it does not run the
deletion commands.

Run `./delete_runai.sh --help` for a summary of modes and environment
variables.

## Modes

Run:ai installs as two components: a control plane (the `runai-backend` Helm
release) and a cluster (the `runai-cluster` Helm release). The script can remove
either one or both.

| Mode | Aliases | Removes |
| --- | --- | --- |
| `all` | `everything` | Both components. This is the default. |
| `control-plane` | `backend`, `cp` | `runai-backend` release and namespace |
| `cluster` | — | `runai-cluster` release, its namespaces, and the cluster-scoped objects it owns |

```bash
./delete_runai.sh                # both (default)
./delete_runai.sh control-plane  # control plane only
./delete_runai.sh cluster        # cluster only
```

The partial modes are scoped so that removing one component does not break the
other:

- **Cluster-scoped objects** (CRDs, admission webhooks, APIServices, priority
  classes) belong to the cluster component. `control-plane` mode leaves them
  in place; `cluster` and `all` remove them.
- **Cluster RBAC** is matched by name, and both components use a `runai`
  prefix. `control-plane` mode matches only `runai-backend`; `cluster` mode
  matches `runai` but excludes `runai-backend`; `all` matches everything
  containing `runai`.
- **Per-project namespaces** belong to the cluster component, so
  `DELETE_PROJECT_NAMESPACES=1` is ignored in `control-plane` mode. The script
  warns when this happens.
- **Secret backups** are limited to the namespaces the selected mode touches.

Because `control-plane` mode leaves cluster-scoped objects alone, tearing down
a full install one component at a time requires finishing with `cluster` (or
running `all`), otherwise CRDs and webhooks remain. The verification summary
says so explicitly when it applies.

Each run prints a deletion plan showing the mode, the Helm releases, the
namespaces, and the RBAC match, before the confirmation prompt.

## Configuration

The script accepts the following environment variables:

- `DRY_RUN=1`: Print deletion commands without executing them.
- `BACKUP_ALL=1`: Back up all non-Helm, non-service-account secrets in the
  namespaces the selected mode touches.
- `ASSUME_YES=1`: Skip the interactive deletion confirmation. Use this only in
  controlled automation.
- `DELETE_PROJECT_NAMESPACES=1`: Also delete per-project namespaces
  (`runai-<project>`) and any other namespace whose name matches `runai`.
  Ignored in `control-plane` mode. See
  [Project namespaces](#project-namespaces) below.
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

Every run does the following:

1. Backs up the prerequisite secrets for the selected mode as re-applicable
   YAML.
2. Aborts before deletion if an existing prerequisite secret cannot be backed
   up.
3. Prints a deletion plan, then asks for confirmation.
4. Uninstalls the in-scope Helm releases, waiting for each to finish.
5. Deletes matching cluster roles and cluster role bindings.
6. Deletes PersistentVolumeClaims in the target namespaces.
7. Deletes the target namespaces.
8. Clears finalizers from those namespaces if they remain in `Terminating`.
9. Prints counts of remaining Run:ai resources for verification.

In `cluster` and `all` modes it additionally deletes, after the Helm uninstall:
admission webhooks, APIServices, and the Run:ai and NVIDIA resource-interface
CRDs (clearing finalizers from their custom resources first), along with the
Run:ai priority classes.

Steps are numbered at runtime, so the numbers shift between modes.

PVCs are deleted explicitly, ahead of the namespaces that contain them, so the
PV reclaim policy still runs if the final sweep has to force-clear a namespace
finalizer. Force-clearing a namespace that still holds PVCs orphans them and
leaves their PVs stranded.

Most deletions use name-based matching, so review the script before using it on
a shared cluster. In particular, the priority classes it removes (`very-high`
through `very-low`) are not named distinctly enough to be unambiguously
Run:ai's; if anything else on the cluster defines a priority class by one of
those names, it will be deleted too.

## Project namespaces

Run:ai creates a namespace per project, named `runai-<project>`. These hold user
workloads and data, so the script leaves them alone by default and deletes only
the fixed namespaces its mode covers.

The deletion plan printed before the confirmation prompt lists any such
namespaces it found and is leaving in place. To remove them as well:

```bash
DELETE_PROJECT_NAMESPACES=1 ./delete_runai.sh
```

This matches any namespace whose name contains `runai`, so confirm the printed
plan before continuing.

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
kubectl get apiservice -o name | grep -Ei 'run\.ai'
```

Commands that produce no output indicate that no matching resources remain.

The summary also reports stranded PVs: PersistentVolumes whose `claimRef` still
points at one of the deleted namespaces. A non-zero count means storage was left
behind and needs manual review:

```bash
kubectl get pv -o wide | grep -Ei 'runai'
```

If you kept the project namespaces, the namespace count in the summary will be
non-zero by design. The script lists the namespaces it deliberately kept so the
count can be reconciled.
