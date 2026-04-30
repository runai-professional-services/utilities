# Integrating JupyterHub with Run:ai

JupyterHub can be configured so that user notebook sessions are scheduled and managed by Run:ai. JupyterHub remains the user-facing entry point; Run:ai handles GPU scheduling, quotas, and workload tracking. The two platforms do not communicate directly — JupyterHub's KubeSpawner creates pods via the Kubernetes API into Run:ai project namespaces, and Run:ai intercepts them at the scheduler level.

**Tested with:** Run:ai 2.24, JupyterHub Helm chart 4.3.4, JupyterHub 5.4.5

## Prerequisites

- A running Run:ai cluster (v2.18+)
- At least one Run:ai project (e.g. a project named `test` → namespace `runai-test`)
- Helm 3 and `kubectl` with cluster access

## Step 1 — Create Namespace and RBAC

JupyterHub needs a namespace and cluster-wide permissions to create pods in `runai-*` namespaces.

```bash
kubectl create namespace jhub
```

Apply the RBAC rules:

```yaml
# jhub-rbac.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: jhub-hub
rules:
- apiGroups: [""]
  resources: [pods, persistentvolumeclaims, services]
  verbs: [get, watch, list, create, delete, patch, update]
- apiGroups: [""]
  resources: [events]
  verbs: [get, watch, list]
- apiGroups: [""]
  resources: [namespaces]
  verbs: [get, list]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jhub-hub
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: jhub-hub
subjects:
- kind: ServiceAccount
  name: hub
  namespace: jhub
```

```bash
kubectl apply -f jhub-rbac.yaml
```

## Step 2 — Create Configuration

Generate a secret token:

```bash
openssl rand -hex 32
```

Create `config.yaml`, replacing `<SECRET-TOKEN>` with the generated value:

```yaml
# config.yaml
hub:
  extraConfig:
    runaiConfig: |
      c.KubeSpawner.scheduler_name = 'runai-scheduler'
      c.KubeSpawner.extra_labels = {
        'project': '{username}',
        'user': '{username}',
      }
      c.KubeSpawner.enable_user_namespaces = True
      # The template below assumes project namespaces follow the default
      # 'runai-<project>' convention. If your namespaces differ, adjust this
      # template or use profile_list with per-profile kubespawner_override
      # to set 'namespace' explicitly per project.
      c.KubeSpawner.user_namespace_template = 'runai-{username}'

      # Run:ai manages project namespaces — skip JupyterHub namespace creation
      async def dummy_ensure_namespace(spawner):
          pass
      c.KubeSpawner.pre_spawn_hook = lambda spawner: setattr(
          spawner, '_ensure_namespace', lambda: dummy_ensure_namespace(spawner)
      )

proxy:
  secretToken: "<SECRET-TOKEN>"

singleuser:
  storage:
    type: none
  profileList:
    - display_name: "CPU Only"
      slug: "cpu"
      description: "Notebook without GPU"
      kubespawner_override:
        image: jupyter/base-notebook:latest
    - display_name: "0.5 GPU (fraction)"
      slug: "half-gpu"
      default: true
      description: "Notebook with 0.5 GPU fraction"
      kubespawner_override:
        image: jupyter/base-notebook:latest
        extra_annotations:
          gpu-fraction: "0.5"
    - display_name: "1 GPU"
      slug: "one-gpu"
      description: "Notebook with 1 full GPU"
      kubespawner_override:
        image: jupyter/base-notebook:latest
        extra_resource_limits:
          nvidia.com/gpu: "1"
```

**Key settings explained:**

| Setting | Purpose |
|---|---|
| `scheduler_name = 'runai-scheduler'` | Pods are scheduled by Run:ai instead of the default K8s scheduler |
| `user_namespace_template = 'runai-{username}'` | Pods land in the namespace derived from the login username. By default, Run:ai project namespaces follow the `runai-<project>` convention, but this is not guaranteed — adjust the template if your namespaces differ |
| `extra_labels` | Lets Run:ai associate the pod with the correct project |
| `pre_spawn_hook` | Prevents JupyterHub from trying to create namespaces that Run:ai already manages |
| `gpu-fraction` annotation | Requests a fractional GPU via Run:ai (see [GPU Fractions docs](https://run-ai-docs.nvidia.com/self-hosted/platform-management/runai-scheduler/resource-optimization/fractions)) |
| `nvidia.com/gpu` resource limit | Requests full GPU(s) via standard Kubernetes device plugin |

## Step 3 — Install

```bash
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo update
helm install jhub jupyterhub/jupyterhub -n jhub --version=4.3.4 --values config.yaml
```

## Verify

Check that all pods are running:

```bash
kubectl get pods -n jhub
```

Access the JupyterHub UI:

```bash
kubectl -n jhub port-forward svc/proxy-public 8080:80
# Open http://localhost:8080
```

**Log in using a Run:ai project name as the username** (e.g. `test`). Any password is accepted with the default authenticator. Select a profile and start a server — the notebook pod will appear in the corresponding `runai-*` namespace and in the Run:ai Workloads UI.

## Notes

- The JupyterHub username must map to an existing Run:ai project namespace. With the default template, user `test` → namespace `runai-test`. Note that Run:ai projects are shared resources (not per-user) — multiple users can log in with the same project name and share its quota. If your project namespaces don't follow the `runai-<project>` convention, adjust `user_namespace_template` accordingly.
- Workloads appear as **Pod** type in the Run:ai UI with full scheduling and quota enforcement.
- No authentication is needed between JupyterHub and Run:ai. Users authenticate to JupyterHub only; Run:ai sees the pods through Kubernetes.
- Customize `singleuser.profileList` to match your GPU types and team needs. Use `extra_annotations` for fractional GPUs and `extra_resource_limits` for full GPUs.
- For production, replace the default JupyterHub authenticator with your organization's identity provider (LDAP, OAuth, etc.).
