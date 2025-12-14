# RunAI GPU Metrics Collector

A Python script to collect GPU metrics from RunAI API at both cluster and project levels.

## Features

This script collects the following GPU metrics:

### Cluster Level Metrics
- **Total GPU requested** (ALLOCATED_GPU) - Number of GPUs currently allocated across all workloads
- **Total GPU limit** (TOTAL_GPU) - Total number of GPUs available in the cluster  
- **Total GPU utilisation** (GPU_UTILIZATION) - Average GPU utilization percentage across the cluster

### Project Level Metrics
- **GPU requested for a project** (allocatedGpus) - Number of GPUs currently allocated to the project
- **GPU limit for a project** (deservedGpus) - GPU quota/limit assigned to the project
- **GPU utilisation for a project** - Current GPU utilization percentage for the project

## Requirements

- Python 3.6+
- Access to RunAI API with valid authentication token
- Network connectivity to RunAI platform

## Installation

1. Clone or download the script files
2. Install Python dependencies:

```bash
pip install -r requirements.txt
```

## Authentication

You need a valid RunAI API bearer token. You can obtain this from:

1. **RunAI CLI**: Run `runai login` and extract the token from the config
2. **RunAI Web UI**: Generate an API token from the platform settings
3. **Environment variables**: Set the token in environment variables for security

## Usage

### Basic Usage

```bash
# Collect metrics from all clusters
python runai_gpu_metrics_collector.py \
  --base-url "https://app.run.ai" \
  --token "your-api-token"

# Collect metrics from a specific cluster
python runai_gpu_metrics_collector.py \
  --base-url "https://app.run.ai" \
  --token "your-api-token" \
  --cluster-uuid "9f55255e-11ed-47c7-acef-fc4054768dbc"
```

### Advanced Usage

```bash
# Collect metrics from last 4 hours and save to file
python runai_gpu_metrics_collector.py \
  --base-url "https://app.run.ai" \
  --token "your-api-token" \
  --hours-back 4 \
  --output-file gpu_metrics.json

# Enable debug logging and disable SSL verification (for testing)
python runai_gpu_metrics_collector.py \
  --base-url "https://app.run.ai" \
  --token "your-api-token" \
  --debug \
  --no-ssl-verify
```

### Using Environment Variables

For security, you can set the token as an environment variable:

```bash
export RUNAI_TOKEN="your-api-token"
python runai_gpu_metrics_collector.py \
  --base-url "https://app.run.ai" \
  --token "$RUNAI_TOKEN"
```

## Command Line Options

| Option | Description | Required | Default |
|--------|-------------|----------|---------|
| `--base-url` | RunAI base URL (e.g., https://app.run.ai) | Yes | - |
| `--token` | RunAI API bearer token | Yes | - |
| `--cluster-uuid` | Specific cluster UUID to collect from | No | All clusters |
| `--hours-back` | Hours of historical data to collect | No | 1 |
| `--output-file` | JSON file to save results | No | stdout |
| `--no-ssl-verify` | Disable SSL certificate verification | No | False |
| `--debug` | Enable debug logging | No | False |

## Output Format

The script outputs metrics in JSON format with the following structure:

```json
{
  "collection_timestamp": "2024-01-15T10:30:00",
  "time_range": {
    "start": "2024-01-15T09:30:00", 
    "end": "2024-01-15T10:30:00"
  },
  "clusters": [
    {
      "cluster_uuid": "9f55255e-11ed-47c7-acef-fc4054768dbc",
      "cluster_name": "production-cluster",
      "cluster_level_metrics": {
        "metrics": {
          "TOTAL_GPU": {
            "current_value": 32,
            "timestamp": "2024-01-15T10:30:00"
          },
          "ALLOCATED_GPU": {
            "current_value": 24,
            "timestamp": "2024-01-15T10:30:00"
          },
          "GPU_UTILIZATION": {
            "current_value": 75.5,
            "timestamp": "2024-01-15T10:30:00"
          }
        }
      },
      "project_level_metrics": [
        {
          "project_name": "team-a",
          "project_id": "proj-123",
          "gpu_metrics": {
            "gpu_limit": 8,
            "gpu_requested": 6,
            "gpu_utilization": 80.2
          }
        }
      ]
    }
  ]
}
```

## Error Handling

The script includes comprehensive error handling:

- **Network errors**: Automatic retry with exponential backoff
- **Authentication errors**: Clear error messages for invalid tokens
- **API errors**: Detailed logging of API response errors
- **Individual project failures**: Continue processing other projects if one fails
- **Missing data**: Graceful handling of missing or incomplete metric data

## Logging

The script uses Python's logging module with different levels:

- **INFO**: General progress and summary information
- **DEBUG**: Detailed API requests and responses (use `--debug` flag)
- **WARNING**: Non-critical issues (e.g., missing project metrics)
- **ERROR**: Critical failures that stop execution

## Troubleshooting

### Common Issues

1. **Authentication Error (401)**
   - Verify your API token is valid and not expired
   - Check that the token has sufficient permissions

2. **Connection Error**
   - Verify the base URL is correct
   - Check network connectivity
   - Use `--no-ssl-verify` if having SSL issues (testing only)

3. **Empty Metrics**
   - The cluster might not have any GPU workloads running
   - Try increasing `--hours-back` to get historical data
   - Verify the cluster has GPU nodes

4. **Missing Project Metrics**
   - Some projects might not have active workloads
   - Check project permissions and access rights

### Debug Mode

Enable debug mode for detailed troubleshooting:

```bash
python runai_gpu_metrics_collector.py \
  --base-url "https://app.run.ai" \
  --token "your-token" \
  --debug
```

This will show:
- All API requests and responses
- Detailed error information
- Data processing steps

## Integration Examples

### Monitoring Systems

```bash
# Collect metrics every 5 minutes and send to monitoring system
*/5 * * * * /usr/bin/python3 /path/to/runai_gpu_metrics_collector.py \
  --base-url "https://app.run.ai" \
  --token "$RUNAI_TOKEN" \
  --output-file /tmp/runai_metrics.json && \
  curl -X POST "http://monitoring-system/api/metrics" \
  -H "Content-Type: application/json" \
  -d @/tmp/runai_metrics.json
```

### Data Pipeline

```python
import subprocess
import json

# Run the collector
result = subprocess.run([
    'python', 'runai_gpu_metrics_collector.py',
    '--base-url', 'https://app.run.ai',
    '--token', 'your-token',
    '--output-file', 'metrics.json'
], capture_output=True, text=True)

# Process the results
with open('metrics.json', 'r') as f:
    metrics = json.load(f)
    
# Send to your data warehouse/analytics platform
```

## API Endpoints Used

The script uses the following RunAI API endpoints:

- `GET /api/v1/clusters` - List available clusters
- `GET /api/v1/clusters/{uuid}/metrics` - Get cluster-level metrics
- `GET /v1/k8s/clusters/{uuid}/projects` - List cluster projects
- `GET /v1/k8s/clusters/{uuid}/projects/quotas` - Get project quotas
- `GET /v1/k8s/clusters/{uuid}/projects/{id}/metrics` - Get project metrics

## Security Considerations

- Store API tokens securely (environment variables, secrets management)
- Use SSL verification in production (`--no-ssl-verify` for testing only)
- Implement token rotation and expiration policies
- Monitor API usage and implement rate limiting if needed

## Contributing

To contribute to this script:

1. Test your changes with multiple clusters and projects
2. Ensure error handling for edge cases
3. Update documentation for any new features
4. Follow Python best practices and PEP 8 style guidelines

## License

This script is provided as-is for use with RunAI platforms. Modify and distribute according to your organization's policies.