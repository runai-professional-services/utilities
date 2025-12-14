#!/usr/bin/env python3
"""
RunAI GPU Metrics Collector

This script collects GPU metrics from RunAI API at both cluster and project levels.

Required metrics:
- Cluster level: Total GPU requested, Total GPU limit, Total GPU utilisation
- Project level: GPU requested, GPU limit, GPU utilisation for each project

Author: Assistant
"""

import argparse
import json
import logging
import os
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class RunAIAPIClient:
    """Client for interacting with RunAI API"""
    
    def __init__(self, base_url: str, token: str, verify_ssl: bool = True):
        """
        Initialize the RunAI API client
        
        Args:
            base_url: RunAI base URL (e.g., 'https://app.run.ai')
            token: Bearer token for authentication
            verify_ssl: Whether to verify SSL certificates
        """
        self.base_url = base_url.rstrip('/')
        self.token = token
        self.verify_ssl = verify_ssl
        
        # Setup session with retry strategy
        self.session = requests.Session()
        retry_strategy = Retry(
            total=3,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["HEAD", "GET", "OPTIONS"]
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)
        
        # Set headers
        self.session.headers.update({
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        })
    
    def _make_request(self, method: str, endpoint: str, params: Dict = None) -> Dict:
        """
        Make HTTP request to RunAI API
        
        Args:
            method: HTTP method (GET, POST, etc.)
            endpoint: API endpoint
            params: Query parameters
            
        Returns:
            Response JSON data
            
        Raises:
            requests.RequestException: If API request fails
        """
        url = f"{self.base_url}{endpoint}"
        
        try:
            logger.debug(f"Making {method} request to: {url}")
            response = self.session.request(
                method=method,
                url=url,
                params=params,
                verify=self.verify_ssl
            )
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            logger.error(f"API request failed: {e}")
            if hasattr(e, 'response') and e.response is not None:
                logger.error(f"Response status: {e.response.status_code}")
                logger.error(f"Response body: {e.response.text}")
            raise
    
    def get_clusters(self) -> List[Dict]:
        """
        Get list of available clusters
        
        Returns:
            List of cluster information
        """
        return self._make_request('GET', '/api/v1/clusters')
    
    def get_cluster_metrics(self, cluster_uuid: str, metric_types: List[str], 
                          start_time: datetime, end_time: datetime, 
                          number_of_samples: int = 20) -> Dict:
        """
        Get cluster-level metrics
        
        Args:
            cluster_uuid: Cluster UUID
            metric_types: List of metric types to retrieve
            start_time: Start time for metrics
            end_time: End time for metrics
            number_of_samples: Number of samples to retrieve
            
        Returns:
            Cluster metrics data
        """
        params = {
            'start': start_time.isoformat(),
            'end': end_time.isoformat(),
            'metricType': metric_types,
            'numberOfSamples': number_of_samples
        }
        
        return self._make_request(
            'GET', 
            f'/api/v1/clusters/{cluster_uuid}/metrics',
            params=params
        )
    
    def get_projects(self, cluster_uuid: str) -> List[Dict]:
        """
        Get list of projects for a cluster
        
        Args:
            cluster_uuid: Cluster UUID
            
        Returns:
            List of project information
        """
        return self._make_request('GET', f'/v1/k8s/clusters/{cluster_uuid}/projects')
    
    def get_projects_quotas(self, cluster_uuid: str) -> List[Dict]:
        """
        Get project quotas for a cluster
        
        Args:
            cluster_uuid: Cluster UUID
            
        Returns:
            List of project quota information
        """
        return self._make_request('GET', f'/v1/k8s/clusters/{cluster_uuid}/projects/quotas')
    
    def get_project_metrics(self, cluster_uuid: str, project_id: str,
                           start_time: datetime, end_time: datetime,
                           number_of_samples: int = 20,
                           nodepool_name: Optional[str] = None) -> Dict:
        """
        Get project-level metrics
        
        Args:
            cluster_uuid: Cluster UUID
            project_id: Project ID
            start_time: Start time for metrics
            end_time: End time for metrics
            number_of_samples: Number of samples to retrieve
            nodepool_name: Optional nodepool filter
            
        Returns:
            Project metrics data
        """
        params = {
            'start': start_time.isoformat(),
            'end': end_time.isoformat(),
            'numberOfSamples': number_of_samples
        }
        
        if nodepool_name:
            params['nodepoolName'] = nodepool_name
        
        return self._make_request(
            'GET',
            f'/v1/k8s/clusters/{cluster_uuid}/projects/{project_id}/metrics',
            params=params
        )


class GPUMetricsCollector:
    """Main class for collecting GPU metrics from RunAI"""
    
    def __init__(self, client: RunAIAPIClient):
        self.client = client
    
    def collect_cluster_gpu_metrics(self, cluster_uuid: str, 
                                  start_time: datetime, end_time: datetime) -> Dict:
        """
        Collect cluster-level GPU metrics
        
        Args:
            cluster_uuid: Cluster UUID
            start_time: Start time for metrics collection
            end_time: End time for metrics collection
            
        Returns:
            Dictionary containing cluster GPU metrics
        """
        logger.info(f"Collecting cluster GPU metrics for {cluster_uuid}")
        
        # Define the metric types we need for cluster level
        cluster_metric_types = [
            'TOTAL_GPU',           # Total GPU limit
            'ALLOCATED_GPU',       # Total GPU requested
            'GPU_UTILIZATION'      # Total GPU utilisation
        ]
        
        try:
            metrics_data = self.client.get_cluster_metrics(
                cluster_uuid=cluster_uuid,
                metric_types=cluster_metric_types,
                start_time=start_time,
                end_time=end_time
            )
            
            # Process the metrics data
            processed_metrics = {
                'cluster_uuid': cluster_uuid,
                'timestamp': datetime.now().isoformat(),
                'time_range': {
                    'start': start_time.isoformat(),
                    'end': end_time.isoformat()
                },
                'metrics': {}
            }
            
            for measurement in metrics_data.get('measurements', []):
                metric_type = measurement.get('type')
                values = measurement.get('values', [])
                
                if values:
                    # Get the latest value
                    latest_value = values[-1] if values else {}
                    processed_metrics['metrics'][metric_type] = {
                        'current_value': latest_value.get('value', 0),
                        'timestamp': latest_value.get('timestamp'),
                        'all_values': values
                    }
            
            return processed_metrics
            
        except Exception as e:
            logger.error(f"Failed to collect cluster metrics: {e}")
            raise
    
    def collect_project_gpu_metrics(self, cluster_uuid: str,
                                   start_time: datetime, end_time: datetime) -> List[Dict]:
        """
        Collect project-level GPU metrics
        
        Args:
            cluster_uuid: Cluster UUID
            start_time: Start time for metrics collection
            end_time: End time for metrics collection
            
        Returns:
            List of dictionaries containing project GPU metrics
        """
        logger.info(f"Collecting project GPU metrics for cluster {cluster_uuid}")
        
        try:
            # Get list of projects
            projects = self.client.get_projects(cluster_uuid)
            logger.info(f"Found {len(projects)} projects")
            
            # Get project quotas (contains GPU limits and allocations)
            quotas = self.client.get_projects_quotas(cluster_uuid)
            
            # Create quota lookup by project name
            quota_lookup = {quota['name']: quota for quota in quotas}
            
            project_metrics = []
            
            for project in projects:
                project_name = project.get('name')
                project_id = project.get('id') or project.get('uuid') or project_name
                
                logger.info(f"Processing project: {project_name} (ID: {project_id})")
                
                try:
                    # Get project metrics (includes utilization)
                    metrics_data = self.client.get_project_metrics(
                        cluster_uuid=cluster_uuid,
                        project_id=str(project_id),
                        start_time=start_time,
                        end_time=end_time
                    )
                    
                    # Get quota information
                    quota_info = quota_lookup.get(project_name, {})
                    
                    project_metric = {
                        'project_name': project_name,
                        'project_id': project_id,
                        'cluster_uuid': cluster_uuid,
                        'timestamp': datetime.now().isoformat(),
                        'time_range': {
                            'start': start_time.isoformat(),
                            'end': end_time.isoformat()
                        },
                        'gpu_metrics': {
                            'gpu_limit': quota_info.get('deservedGpus', 0),  # GPU limit (quota)
                            'gpu_requested': quota_info.get('allocatedGpus', 0),  # GPU requested
                            'gpu_utilization': self._extract_gpu_utilization(metrics_data)
                        },
                        'raw_metrics': metrics_data,
                        'raw_quota': quota_info
                    }
                    
                    project_metrics.append(project_metric)
                    
                except Exception as e:
                    logger.warning(f"Failed to get metrics for project {project_name}: {e}")
                    # Add project with empty metrics
                    project_metrics.append({
                        'project_name': project_name,
                        'project_id': project_id,
                        'cluster_uuid': cluster_uuid,
                        'timestamp': datetime.now().isoformat(),
                        'error': str(e),
                        'gpu_metrics': {
                            'gpu_limit': quota_lookup.get(project_name, {}).get('deservedGpus', 0),
                            'gpu_requested': quota_lookup.get(project_name, {}).get('allocatedGpus', 0),
                            'gpu_utilization': 0
                        }
                    })
            
            return project_metrics
            
        except Exception as e:
            logger.error(f"Failed to collect project metrics: {e}")
            raise
    
    def _extract_gpu_utilization(self, metrics_data: Dict) -> float:
        """
        Extract GPU utilization from project metrics data
        
        Args:
            metrics_data: Raw metrics data from API
            
        Returns:
            GPU utilization percentage (0-100)
        """
        try:
            # Look for GPU utilization in current metrics
            current = metrics_data.get('current', {})
            resources = current.get('resources', [])
            
            for resource in resources:
                if resource.get('type') == 'gpu':
                    utilization = resource.get('utilization', {})
                    if 'percentage' in utilization:
                        return float(utilization['percentage'])
                    elif 'value' in utilization:
                        return float(utilization['value'])
            
            # Alternative: look in timeRange data if available
            time_range = metrics_data.get('timeRange', {})
            data_points = time_range.get('data', [])
            
            if data_points:
                for data_point in data_points:
                    resources = data_point.get('resources', [])
                    for resource in resources:
                        if resource.get('type') == 'gpu':
                            utilization = resource.get('utilization', {})
                            if 'percentage' in utilization:
                                return float(utilization['percentage'])
                            elif 'value' in utilization:
                                return float(utilization['value'])
                
                # If we have data points, return the latest utilization value
                latest_data = data_points[-1]
                return latest_data.get('gpu_utilization', 0)
            
            return 0.0
            
        except Exception as e:
            logger.warning(f"Failed to extract GPU utilization: {e}")
            return 0.0
    
    def collect_all_metrics(self, cluster_uuid: Optional[str] = None,
                          hours_back: int = 1) -> Dict:
        """
        Collect all GPU metrics (cluster and project level)
        
        Args:
            cluster_uuid: Specific cluster UUID, or None to collect from all clusters
            hours_back: How many hours back to collect metrics
            
        Returns:
            Dictionary containing all collected metrics
        """
        end_time = datetime.now()
        start_time = end_time - timedelta(hours=hours_back)
        
        logger.info(f"Collecting metrics from {start_time} to {end_time}")
        
        all_metrics = {
            'collection_timestamp': datetime.now().isoformat(),
            'time_range': {
                'start': start_time.isoformat(),
                'end': end_time.isoformat()
            },
            'clusters': []
        }
        
        try:
            # Get clusters to process
            if cluster_uuid:
                clusters_to_process = [{'uuid': cluster_uuid}]
            else:
                clusters_to_process = self.client.get_clusters()
            
            for cluster in clusters_to_process:
                cluster_id = cluster.get('uuid') or cluster.get('id')
                cluster_name = cluster.get('name', cluster_id)
                
                logger.info(f"Processing cluster: {cluster_name} ({cluster_id})")
                
                cluster_metrics = {
                    'cluster_uuid': cluster_id,
                    'cluster_name': cluster_name,
                    'cluster_level_metrics': {},
                    'project_level_metrics': []
                }
                
                try:
                    # Collect cluster-level metrics
                    cluster_gpu_metrics = self.collect_cluster_gpu_metrics(
                        cluster_uuid=cluster_id,
                        start_time=start_time,
                        end_time=end_time
                    )
                    cluster_metrics['cluster_level_metrics'] = cluster_gpu_metrics
                    
                except Exception as e:
                    logger.error(f"Failed to collect cluster metrics for {cluster_name}: {e}")
                    cluster_metrics['cluster_level_metrics'] = {'error': str(e)}
                
                try:
                    # Collect project-level metrics
                    project_gpu_metrics = self.collect_project_gpu_metrics(
                        cluster_uuid=cluster_id,
                        start_time=start_time,
                        end_time=end_time
                    )
                    cluster_metrics['project_level_metrics'] = project_gpu_metrics
                    
                except Exception as e:
                    logger.error(f"Failed to collect project metrics for {cluster_name}: {e}")
                    cluster_metrics['project_level_metrics'] = [{'error': str(e)}]
                
                all_metrics['clusters'].append(cluster_metrics)
            
            return all_metrics
            
        except Exception as e:
            logger.error(f"Failed to collect metrics: {e}")
            raise


def main():
    """Main function to run the metrics collector"""
    parser = argparse.ArgumentParser(description='Collect GPU metrics from RunAI API')
    parser.add_argument('--base-url', 
                       default=os.environ.get('RUNAI_BASE_URL'),
                       help='RunAI base URL (e.g., https://app.run.ai). Can also use RUNAI_BASE_URL env var.')
    parser.add_argument('--token', 
                       default=os.environ.get('RUNAI_TOKEN'),
                       help='RunAI API bearer token. Can also use RUNAI_TOKEN env var.')
    parser.add_argument('--cluster-uuid', 
                       help='Specific cluster UUID to collect metrics from')
    parser.add_argument('--hours-back', type=int, default=1,
                       help='How many hours back to collect metrics (default: 1)')
    parser.add_argument('--output-file',
                       help='Output file to save metrics (JSON format)')
    parser.add_argument('--no-ssl-verify', action='store_true',
                       help='Disable SSL certificate verification')
    parser.add_argument('--debug', action='store_true',
                       help='Enable debug logging')
    
    args = parser.parse_args()
    
    # Validate required arguments
    if not args.base_url:
        parser.error("--base-url is required (or set RUNAI_BASE_URL environment variable)")
    if not args.token:
        parser.error("--token is required (or set RUNAI_TOKEN environment variable)")
    
    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Initialize API client
    client = RunAIAPIClient(
        base_url=args.base_url,
        token=args.token,
        verify_ssl=not args.no_ssl_verify
    )
    
    # Initialize metrics collector
    collector = GPUMetricsCollector(client)
    
    try:
        # Collect all metrics
        metrics = collector.collect_all_metrics(
            cluster_uuid=args.cluster_uuid,
            hours_back=args.hours_back
        )
        
        # Output results
        if args.output_file:
            with open(args.output_file, 'w') as f:
                json.dump(metrics, f, indent=2)
            logger.info(f"Metrics saved to {args.output_file}")
        else:
            print(json.dumps(metrics, indent=2))
        
        # Print summary
        logger.info("=== METRICS COLLECTION SUMMARY ===")
        for cluster_data in metrics['clusters']:
            cluster_name = cluster_data['cluster_name']
            logger.info(f"\nCluster: {cluster_name}")
            
            # Cluster level summary
            cluster_metrics = cluster_data['cluster_level_metrics'].get('metrics', {})
            if cluster_metrics:
                total_gpu = cluster_metrics.get('TOTAL_GPU', {}).get('current_value', 'N/A')
                allocated_gpu = cluster_metrics.get('ALLOCATED_GPU', {}).get('current_value', 'N/A')
                gpu_util = cluster_metrics.get('GPU_UTILIZATION', {}).get('current_value', 'N/A')
                
                logger.info(f"  Total GPUs: {total_gpu}")
                logger.info(f"  Allocated GPUs: {allocated_gpu}")
                logger.info(f"  GPU Utilization: {gpu_util}%")
            
            # Project level summary
            projects = cluster_data['project_level_metrics']
            logger.info(f"  Projects: {len(projects)}")
            
            for project in projects[:5]:  # Show first 5 projects
                if 'error' not in project:
                    gpu_metrics = project['gpu_metrics']
                    logger.info(f"    {project['project_name']}: "
                              f"Limit={gpu_metrics['gpu_limit']}, "
                              f"Requested={gpu_metrics['gpu_requested']}, "
                              f"Utilization={gpu_metrics['gpu_utilization']}%")
        
        return 0
        
    except Exception as e:
        logger.error(f"Failed to collect metrics: {e}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
