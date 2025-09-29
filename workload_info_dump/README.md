# Workload Info Dump v2.3.0

Efficiently collects and archives Run:AI workload information with optimized per-pod resource gathering.

## Usage

```sh
./start.sh --project <PROJECT> --type <TYPE> --workload <WORKLOAD>
```

### Parameters
- **PROJECT**: Run:AI project name
- **WORKLOAD**: Workload name  
- **TYPE**: Workload type - `iw`, `tw`, `dw`, `infw`, `dinfw`, `ew`

### Example
```sh
./start.sh --project test --type dw --workload my-training
```

## What it collects

**Per-pod files (organized by pod name):**
- Pod YAML manifests
- Pod descriptions  
- Container logs
- nvidia-smi output (if available)

**Workload-level files:**
- Workload YAML (DistributedWorkload, TrainingWorkload, etc.)
- RunAIJob YAML
- PodGroup YAML
- KSVC YAML (inference workloads only)

**Namespace-level files:**
- Pod list (wide format)
- ConfigMaps
- PVCs

## Output

Creates timestamped archive: `<PROJECT>_<TYPE>_<WORKLOAD>_v<VERSION>_<TIMESTAMP>.tar.gz`

**File naming convention:**
- Pod files: `<workload>_<type>_pod_<pod-name>_<resource>.<ext>`
- Example: `my-training_dw_pod_worker-0_logs_pytorch.log`

## Features

✅ **Optimized**: Single discovery pass with unified pod processing  
✅ **Organized**: Separate files per pod for easy analysis  
✅ **Resilient**: Continues on individual resource failures  
✅ **Comprehensive**: Collects all relevant Kubernetes resources