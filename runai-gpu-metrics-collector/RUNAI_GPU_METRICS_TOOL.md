# RunAI GPU Metrics Collection Tool

This repository now includes a comprehensive GPU metrics collection tool for RunAI platforms.

## Location

All GPU metrics collection tool files are located in:

```
./runai-gpu-metrics-collector/
```

## What's Included

The `runai-gpu-metrics-collector/` directory contains:

- **`runai_gpu_metrics_collector.py`** - Main Python script for collecting GPU metrics
- **`README.md`** - Comprehensive documentation and usage guide
- **`requirements.txt`** - Python dependencies
- **`test_runai_metrics.py`** - Test suite for validation
- **`config.example.env`** - Example configuration file

## Quick Start

1. Navigate to the tool directory:
   ```bash
   cd runai-gpu-metrics-collector/
   ```

2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Run the collector:
   ```bash
   python3 runai_gpu_metrics_collector.py \
     --base-url "https://app.run.ai" \
     --token "your-api-token"
   ```

## Features

This tool collects GPU metrics at two levels:

### Cluster Level
- Total GPU requested (allocated across all workloads)
- Total GPU limit (total available GPUs)
- Total GPU utilization (average across cluster)

### Project Level
- GPU requested per project
- GPU limit per project
- GPU utilization per project

## Output

The tool outputs comprehensive JSON data that can be:
- Saved to files for analysis
- Integrated with monitoring systems
- Used in data pipelines
- Processed for reporting

For complete documentation, see `runai-gpu-metrics-collector/README.md`.
