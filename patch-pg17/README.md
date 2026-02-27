# patch-pg17

Patch for Run:ai control-plane v2.24.51 when running against PostgreSQL 17.

## Problem

The `check-postgres-readiness` init container ships with `postgresql16-server`, whose `psql` `\l` meta-command references `d.daticulocale` — a column that was renamed in PostgreSQL 17. This causes readiness checks to fail on PG17 clusters.

**Case:** 01087689

## What the patch does

The script iterates over all Deployments and StatefulSets in the Run:ai backend namespace, finds any that include a `check-postgres-readiness` init container, and performs a strategic-merge patch to:

1. Replace the init container image with `ghcr.io/cloudnative-pg/postgresql:17.5` (PG17-compatible `psql` client).
2. Set `runAsNonRoot: true` on the init container's security context (compatible with OpenShift restricted SCCs).
3. Delete the `keycloak-0` pod to trigger a restart with the patched configuration.

## Usage

```bash
./patch-pg17.sh [NAMESPACE] [IMAGE]
```

| Argument    | Default                                   | Description                              |
|-------------|-------------------------------------------|------------------------------------------|
| `NAMESPACE` | `runai-backend`                           | Kubernetes namespace for Run:ai backend  |
| `IMAGE`     | `ghcr.io/cloudnative-pg/postgresql:17.5`  | Replacement image for the init container |

### Examples

Patch with defaults:

```bash
./patch-pg17.sh
```

Patch a custom namespace:

```bash
./patch-pg17.sh my-runai-namespace
```

Patch with a different image:

```bash
./patch-pg17.sh runai-backend my-registry.example.com/postgresql:17.5
```

## Post-patch

Affected pods will restart automatically. Monitor the rollout with:

```bash
kubectl -n <NAMESPACE> get pods -w
```

## Prerequisites

- `kubectl` configured with access to the target cluster
- Permissions to patch Deployments/StatefulSets and delete pods in the target namespace
