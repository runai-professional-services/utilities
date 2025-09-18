# Workload Info Dump

Collects and archives Run:AI workload information and related Kubernetes resources.

## Usage

```sh
./start.sh --project <PROJECT> --type <TYPE> --workload <WORKLOAD>
```

**Parameters:**
- `<PROJECT>`: Run:AI project name
- `<WORKLOAD>`: Workload name  
- `<TYPE>`: Workload type - `iw`, `tw`, `dw`, `infw`, `dinfw`, `ew`

**Example:**
```sh
./start.sh --project test --type tw --workload test-train
```

## What it collects

- Workload, RunAIJob, Pod, PodGroup YAML manifests
- Pod logs from all containers
- Pod descriptions for all pods in namespace
- Pod list (wide format) for all pods in namespace
- KSVC YAML (inference workloads only)

Creates timestamped archive: `<PROJECT>_<TYPE>_<WORKLOAD>_<TIMESTAMP>.tar.gz`
