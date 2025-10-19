# Enabling Advanced GPU Metrics in Run:ai

This guide enables advanced GPU profiling metrics from NVIDIA DCGM, including SM activity, memory bandwidth utilization, tensor core usage, and compute pipeline metrics. These metrics provide deeper insights into GPU performance beyond basic utilization.

> **Reference**: [NVIDIA DCGM Metrics Documentation](https://docs.nvidia.com/datacenter/dcgm/latest/user-guide/feature-overview.html#metrics)

## Prerequisites

- NVIDIA GPU Operator installed
- Helm 3.x installed
- kubectl access to the cluster
- Run:ai cluster installation

---

## Step 1: Configure DCGM Exporter

Configure the DCGM exporter to collect advanced profiling metrics.

### 1.1 Create Metrics Configuration

Save the following as `dcgm-metrics.csv`:

```csv
# DCGM FIELD, Prometheus metric type, help message

# Clocks
DCGM_FI_DEV_SM_CLOCK,  gauge, SM clock frequency (in MHz).
DCGM_FI_DEV_MEM_CLOCK, gauge, Memory clock frequency (in MHz).

# Temperature
DCGM_FI_DEV_MEMORY_TEMP, gauge, Memory temperature (in C).
DCGM_FI_DEV_GPU_TEMP,    gauge, GPU temperature (in C).

# Power
DCGM_FI_DEV_POWER_USAGE,              gauge, Power draw (in W).
DCGM_FI_DEV_TOTAL_ENERGY_CONSUMPTION, counter, Total energy consumption since boot (in mJ).

# PCIE
DCGM_FI_DEV_PCIE_REPLAY_COUNTER, counter, Total number of PCIe retries.

# Utilization
DCGM_FI_DEV_GPU_UTIL,      gauge, GPU utilization (in %).
DCGM_FI_DEV_MEM_COPY_UTIL, gauge, Memory utilization (in %).
DCGM_FI_DEV_ENC_UTIL,      gauge, Encoder utilization (in %).
DCGM_FI_DEV_DEC_UTIL ,     gauge, Decoder utilization (in %).

# Errors
DCGM_FI_DEV_XID_ERRORS, gauge, Value of the last XID error encountered.

# Memory
DCGM_FI_DEV_FB_FREE, gauge, Framebuffer memory free (in MiB).
DCGM_FI_DEV_FB_USED, gauge, Framebuffer memory used (in MiB).

# NVLink
DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL, counter, Total number of NVLink bandwidth counters for all lanes.
DCGM_FI_DEV_NVLINK_BANDWIDTH_L0,    counter, The number of bytes of active NVLink rx or tx data including both header and payload.

# vGPU
DCGM_FI_DEV_VGPU_LICENSE_STATUS, gauge, vGPU License status

# Remapped rows
DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS, counter, Number of remapped rows for uncorrectable errors
DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS,   counter, Number of remapped rows for correctable errors
DCGM_FI_DEV_ROW_REMAP_FAILURE,           gauge,   Whether remapping of rows has failed

# Labels
DCGM_FI_DRIVER_VERSION, label, Driver Version

# DCP Profiling Metrics (Advanced)
DCGM_FI_PROF_GR_ENGINE_ACTIVE,   gauge, Ratio of time the graphics engine is active (in %).
DCGM_FI_PROF_SM_ACTIVE,          gauge, The ratio of cycles an SM has at least 1 warp assigned (in %).
DCGM_FI_PROF_SM_OCCUPANCY,       gauge, The ratio of number of warps resident on an SM (in %).
DCGM_FI_PROF_PIPE_TENSOR_ACTIVE, gauge, Ratio of cycles the tensor (HMMA) pipe is active (in %).
DCGM_FI_PROF_DRAM_ACTIVE,        gauge, Ratio of cycles the device memory interface is active sending or receiving data (in %).
DCGM_FI_PROF_PIPE_FP64_ACTIVE,   gauge, Ratio of cycles the fp64 pipes are active (in %).
DCGM_FI_PROF_PIPE_FP32_ACTIVE,   gauge, Ratio of cycles the fp32 pipes are active (in %).
DCGM_FI_PROF_PIPE_FP16_ACTIVE,   gauge, Ratio of cycles the fp16 pipes are active (in %).
DCGM_FI_PROF_PCIE_TX_BYTES,      gauge, The rate of data transmitted over the PCIe bus - including both protocol headers and data payloads - in bytes per second.
DCGM_FI_PROF_PCIE_RX_BYTES,      gauge, The rate of data received over the PCIe bus - including both protocol headers and data payloads - in bytes per second.
DCGM_FI_PROF_NVLINK_TX_BYTES,    gauge, The number of bytes of active NvLink tx (transmit) data including both header and payload.
DCGM_FI_PROF_NVLINK_RX_BYTES,    gauge, The number of bytes of active NvLink rx (read) data including both header and payload
```

### 1.2 Create Helm Values File

Save the following as `extended-dcgm-metrics-values.yaml`:

```yaml
dcgmExporter:
  config:
    name: metrics-config
  env:
    - name: DCGM_EXPORTER_COLLECTORS
      value: /etc/dcgm-exporter/dcgm-metrics.csv
```

### 1.3 Apply Configuration

```bash
# Get GPU Operator version
GPU_OPERATOR_VERSION=$(helm ls -A | grep gpu-operator | awk '{ print $10 }')

# Create ConfigMap with metrics configuration
kubectl create configmap metrics-config -n gpu-operator --from-file=dcgm-metrics.csv

# Upgrade GPU Operator with new configuration
helm upgrade -i gpu-operator nvidia/gpu-operator \
  -n gpu-operator \
  --version $GPU_OPERATOR_VERSION \
  --reuse-values \
  -f extended-dcgm-metrics-values.yaml
```

The DCGM exporter DaemonSet will automatically restart with the new configuration.

---

## Step 2: Enable Run:ai Advanced Metrics

Enable Run:ai to create enriched metrics from the DCGM profiling data. This configures Prometheus recording rules that aggregate raw DCGM metrics per pod, workload, node, and nodepool.

```bash
kubectl patch runaiconfig runai -n runai \
  --type=merge \
  -p '{
    "spec": {
      "prometheus": {
        "config": {
          "advancedMetricsEnabled": true
        }
      }
    }
  }'
```

---

## Verification

### Command Line

Verify the metrics are being collected:

```bash
# Check DCGM exporter pods are running
kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter

# Check for advanced metrics in Prometheus (if accessible)
# Look for metrics like: DCGM_FI_PROF_SM_ACTIVE, DCGM_FI_PROF_DRAM_ACTIVE
# And Run:ai enriched metrics like: runai_gpu_sm_active_per_pod_per_gpu
```

### UI Verification

**Workloads:**
1. Navigate to a workload's details page
2. Go to the **Metrics** tab
3. In the **Type** dropdown, verify the **"Advanced"** option is available

**Nodes:**
1. Go to the **Nodes** page
2. Select a node and click **"View Details"**
3. Go to the **Metrics** section
4. Verify **"Advanced"** metrics are displayed

---

## Available Advanced Metrics

Once enabled, the following advanced metric categories are available:

- **SM Activity**: SM active cycles and occupancy
- **Memory Bandwidth**: DRAM active cycles
- **Compute Pipelines**: FP16/FP32/FP64 and Tensor core activity
- **Graphics Engine**: GR engine utilization
- **PCIe/NVLink**: Data transfer rates

Run:ai creates aggregated versions at multiple levels:
- Per GPU device
- Per pod
- Per workload
- Per node
- Per nodepool
