# GPU CDI Debug Collection

Scripts to collect GPU Operator / CDI (Container Device Interface) state for debugging. Output goes to `~/runai-cdi-collect-YYYYMMDD/` (and a `.tar.gz` from the cluster run).

## How to run

1. **On one GPU node** (SSH or console): run `node.sh`.  
   - Collects CDI dirs, containerd config, toolkit config, driver paths, and mounts on that node.

2. **From a machine with `kubectl` (and `helm`)**: run `cluster.sh`.  
   - Collects ClusterPolicy, Helm values, GPU Operator DaemonSets, and toolkit pod logs.  
   - To capture logs from the same node you ran `node.sh` on, set `NODE_NAME` before running:
     ```bash
     export NODE_NAME=ip-172-20-10-160   # your GPU node name
     ./cluster.sh
     ```

3. Share the archive: `~/runai-cdi-collect-YYYYMMDD.tar.gz`.

## What each script does

- **node.sh** — On a single GPU node: lists `/etc/cdi` and `/var/run/cdi`, dumps containerd config, toolkit config, `nvidia-container-cli info`, driver paths, toolkit processes/mounts, and BCM `conf.d` TOML files. All output is written into the date-stamped directory.

- **cluster.sh** — From a cluster-admin machine: saves ClusterPolicy, GPU Operator Helm values, toolkit and device-plugin DaemonSet YAML, and logs from the toolkit pod on `NODE_NAME` (if set). Then tars the directory into `~/runai-cdi-collect-YYYYMMDD.tar.gz`.

## Requirements

- **node.sh**: Bash; run as root or with access to `/etc/cdi`, `/var/run/cdi`, containerd, and nvidia toolkit paths.
- **cluster.sh**: `kubectl` and `helm`, with access to the `gpu-operator` namespace.
