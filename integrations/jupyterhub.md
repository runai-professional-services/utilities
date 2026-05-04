# Integrating JupyterHub with Run:ai

JupyterHub can be configured so that user notebook sessions are scheduled and managed by Run:ai. JupyterHub remains the user-facing entry point; Run:ai handles GPU scheduling, quotas, and workload tracking. The two platforms do not communicate directly. JupyterHub's KubeSpawner creates pods via the Kubernetes API into Run:ai project namespaces, and Run:ai intercepts them at the scheduler level.

JupyterHub is deployed on the same Kubernetes cluster as Run:ai using the standard Helm chart and exposed externally via Ingress or LoadBalancer.

**Tested with:** Run:ai 2.24, JupyterHub Helm chart 4.3.4, JupyterHub 5.4.5

## Prerequisites

- A running Run:ai cluster (v2.18+)
- At least one Run:ai project (e.g. a project named `test` with namespace `runai-test`)
- `kubectl` with cluster access
- Helm 3

## Step 1 -- RBAC

JupyterHub needs cluster-wide permissions to create and manage pods in Run:ai project namespaces.

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
kubectl create namespace jhub
kubectl apply -f jhub-rbac.yaml
```

## Step 2 -- Configuration

**Key settings explained:**

| Setting | Purpose |
|---|---|
| `scheduler_name = 'runai-scheduler'` | Notebook pods are scheduled by Run:ai instead of the default K8s scheduler |
| `user_namespace_template = 'runai-{username}'` | Pods land in the namespace derived from the login username. By default Run:ai project namespaces follow the `runai-<project>` convention, but this is not guaranteed; adjust the template if your namespaces differ |
| `extra_labels` | Lets Run:ai associate the pod with the correct project |
| `pre_spawn_hook` | Prevents JupyterHub from trying to create namespaces that Run:ai already manages |
| `gpu-fraction` annotation | Requests a fractional GPU via Run:ai |
| `nvidia.com/gpu` resource limit | Requests full GPU(s) via standard Kubernetes device plugin |

Generate a secret token:

```bash
openssl rand -hex 32
```

Create `config.yaml`, replacing `<SECRET-TOKEN>` with the generated value:

```yaml
# config.yaml
hub:
  nodeSelector:
    # Schedule hub on infrastructure/CPU-only nodes, not on GPU compute nodes.
    # Replace with a label that matches your dedicated node pool.
    node-role.kubernetes.io/infra: ""
  tolerations:
    - key: "node-role.kubernetes.io/infra"
      operator: "Exists"
      effect: "NoSchedule"
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

      # Run:ai manages project namespaces -- skip JupyterHub namespace creation
      async def dummy_ensure_namespace(spawner):
          pass
      c.KubeSpawner.pre_spawn_hook = lambda spawner: setattr(
          spawner, '_ensure_namespace', lambda: dummy_ensure_namespace(spawner)
      )

proxy:
  secretToken: "<SECRET-TOKEN>"
  nodeSelector:
    node-role.kubernetes.io/infra: ""
  tolerations:
    - key: "node-role.kubernetes.io/infra"
      operator: "Exists"
      effect: "NoSchedule"

scheduling:
  userScheduler:
    enabled: false  # Run:ai handles all scheduling for notebook pods

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

### Node placement

The `hub.nodeSelector` and `proxy.nodeSelector` fields ensure that JupyterHub's infrastructure pods (hub and proxy) land on dedicated CPU/infrastructure nodes rather than on GPU compute nodes. Adjust the label and toleration to match your cluster's node pool setup. Common patterns:

| Node pool label | Example |
|---|---|
| `node-role.kubernetes.io/infra: ""` | Dedicated infra nodes |
| `run.ai/type: system` | Run:ai system node pool |
| `nodepool: cpu` | Custom CPU-only pool |

If your infrastructure nodes use a taint to repel workloads (e.g. `node-role.kubernetes.io/infra:NoSchedule`), the `tolerations` section lets the hub and proxy pods schedule there. If your infrastructure nodes have no taints, you can omit the `tolerations` and keep only `nodeSelector`.

The notebook pods themselves (spawned by KubeSpawner) are scheduled by Run:ai onto GPU or CPU nodes based on the selected profile. Their placement is controlled by Run:ai's scheduler and node pool configuration, not by JupyterHub.

## Step 3 -- Install

```bash
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo update
helm install jhub jupyterhub/jupyterhub -n jhub --version=4.3.4 --values config.yaml
```

Wait for pods to be ready:

```bash
kubectl get pods -n jhub
```

## Step 4 -- Expose externally

Access JupyterHub via port-forward for testing:

```bash
kubectl -n jhub port-forward svc/proxy-public 8080:80
# Open http://localhost:8080
```

For production, expose JupyterHub externally using an Ingress or LoadBalancer. Example with Ingress:

```yaml
ingress:
  enabled: true
  hosts:
    - jupyterhub.example.com
```

Or set the proxy service to LoadBalancer:

```yaml
proxy:
  service:
    type: LoadBalancer
```

## Step 5 -- Verify

Log in using a Run:ai project name as the username (e.g. `test`). Any password is accepted with the default authenticator. Select a profile and start a server. The notebook pod will appear in the corresponding `runai-*` namespace and in the Run:ai Workloads UI.

```bash
kubectl get pods -n runai-test
```

## Notes

- The JupyterHub username must map to an existing Run:ai project namespace. With the default template, user `test` maps to namespace `runai-test`. Run:ai projects are shared resources (not per-user); multiple users can log in with the same project name and share its quota. If your project namespaces don't follow the `runai-<project>` convention, adjust `user_namespace_template` accordingly.
- Workloads appear as **Pod** type in the Run:ai UI with full scheduling and quota enforcement.
- No authentication is needed between JupyterHub and Run:ai. Users authenticate to JupyterHub only; Run:ai sees the pods through Kubernetes.
- Customize the profile list to match your GPU types and team needs. Use `extra_annotations` for fractional GPUs and `extra_resource_limits` for full GPUs.
- Pods are named `jupyter-{username}`. If multiple users share the same project name, only one can have an active notebook at a time under that name.
- `storage: type: none` means notebook data is not persisted between sessions. For production, configure persistent storage via `singleuser.storage` to retain user work.
- For production, replace the default JupyterHub authenticator with your organization's identity provider (LDAP, OAuth, etc.).
