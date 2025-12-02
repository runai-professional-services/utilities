# GPU Simple Test

A simple utility to test GPU availability in a Kubernetes cluster by running nvidia-smi in a pod.

## Description

This script creates a Kubernetes pod that requests a single GPU and runs the `nvidia-smi` command. It monitors the pod's execution status, collects logs and diagnostics, and archives the results.

## Prerequisites

- `kubectl` configured and connected to your cluster
- A Kubernetes cluster with GPU nodes
- Appropriate permissions to create pods and view logs

## Usage

### Basic Usage

```bash
./start.sh
```

### Advanced Usage

You can customize the behavior using environment variables:

```bash
# Run in a specific namespace
NAMESPACE=my-namespace ./start.sh

# Set custom timeout (default: 300 seconds)
TIMEOUT=600 ./start.sh

# Combine options
NAMESPACE=gpu-workloads TIMEOUT=120 ./start.sh
```

## What It Does

1. **Cleanup**: Removes any existing `gpu-test` pod
2. **Create Pod**: Deploys a pod using the nvidia/cuda:11.8.0-base-ubuntu22.04 image
3. **Monitor**: Watches the pod status with detailed progress tracking:
   - Pod scheduling status
   - Image pull progress
   - Container creation and initialization
   - Container state changes (Waiting, Running, Terminated)
   - Real-time status updates every 3 seconds
4. **Collect**: Gathers the following information:
   - Pod logs (nvidia-smi output)
   - Pod description
   - Pod YAML manifest
   - Pod events
   - Summary with status and timing
5. **Archive**: Creates a timestamped tar.gz archive with all collected data
6. **Display**: Shows the nvidia-smi output if successful (or error details if failed)
7. **Cleanup**: Optionally deletes the test pod

## Output

The script creates an archive named `gpu-test-results-YYYYMMDD-HHMMSS.tar.gz` containing:

- `pod-logs.txt` - The nvidia-smi command output
- `pod-describe.txt` - Detailed pod description
- `pod.yaml` - Pod manifest
- `pod-events.txt` - Kubernetes events related to the pod
- `summary.txt` - Test summary with status and timing

## Exit Codes

- `0` - Pod completed successfully
- `1` - Pod failed, timed out, or encountered an error

## Example Output

```
=== GPU Simple Test ===
Pod Name: gpu-test
Namespace: default
Timeout: 300s

Checking for existing pod...
Creating GPU test pod...
Monitoring pod status...
  Phase: Pending | Container: Scheduling | Elapsed: 0s
  Phase: Pending | Container: Initializing | Elapsed: 2s
  Phase: Pending | Container: ContainerCreating | Elapsed: 5s
    Pulling image: nvidia/cuda:11.8.0-base-ubuntu22.04
  Phase: Running | Container: Running | Elapsed: 15s
  Phase: Succeeded | Elapsed: 18s
Pod completed successfully!

=== Collecting Pod Information ===
Collecting pod describe output...
Collecting pod logs...
Collecting pod YAML...
Collecting pod events...
Creating summary...

Creating archive: gpu-test-results-20251202-143022.tar.gz
=== Results ===
Status: Succeeded
Archive created: gpu-test-results-20251202-143022.tar.gz

=== nvidia-smi Output ===
[nvidia-smi output here]

Done! Results saved in: gpu-test-results-20251202-143022.tar.gz
```

## Troubleshooting

If the pod fails to start or complete:

1. Check that your cluster has GPU nodes with available GPUs
2. Verify GPU operator/device plugin is installed and running
3. Review the collected logs and describe output in the archive
4. Check for pod events indicating scheduling issues
5. Ensure the namespace has access to GPU resources

## Files

- `start.sh` - Main script that orchestrates the test
- `gpu-test.yaml` - Pod definition with GPU request
- `README.md` - This file

