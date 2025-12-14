#!/usr/bin/env python3
"""
Simple test script for RunAI GPU Metrics Collector

This script performs basic validation of the metrics collector
without making actual API calls.
"""

import json
import sys
import tempfile
from datetime import datetime, timedelta
from unittest.mock import Mock, patch

# Import the main module
try:
    from runai_gpu_metrics_collector import RunAIAPIClient, GPUMetricsCollector
except ImportError:
    print("Error: Could not import runai_gpu_metrics_collector module")
    sys.exit(1)


def test_api_client_initialization():
    """Test API client initialization"""
    print("Testing API client initialization...")
    
    client = RunAIAPIClient(
        base_url="https://test.run.ai",
        token="test-token",
        verify_ssl=False
    )
    
    assert client.base_url == "https://test.run.ai"
    assert client.token == "test-token"
    assert client.verify_ssl == False
    assert "Bearer test-token" in client.session.headers['Authorization']
    
    print("✓ API client initialization test passed")


def test_metrics_collector_initialization():
    """Test metrics collector initialization"""
    print("Testing metrics collector initialization...")
    
    client = RunAIAPIClient("https://test.run.ai", "test-token")
    collector = GPUMetricsCollector(client)
    
    assert collector.client == client
    
    print("✓ Metrics collector initialization test passed")


def test_gpu_utilization_extraction():
    """Test GPU utilization extraction from various data formats"""
    print("Testing GPU utilization extraction...")
    
    client = RunAIAPIClient("https://test.run.ai", "test-token")
    collector = GPUMetricsCollector(client)
    
    # Test case 1: Utilization in current.resources
    test_data_1 = {
        "current": {
            "resources": [
                {
                    "type": "gpu",
                    "utilization": {
                        "percentage": 85.5
                    }
                }
            ]
        }
    }
    
    result = collector._extract_gpu_utilization(test_data_1)
    print(f"Test 1 result: {result}")
    assert result == 85.5
    
    # Test case 2: Utilization in timeRange.data
    test_data_2 = {
        "timeRange": {
            "data": [
                {
                    "resources": [
                        {
                            "type": "gpu",
                            "utilization": {
                                "value": 67.3
                            }
                        }
                    ]
                }
            ]
        }
    }
    
    result = collector._extract_gpu_utilization(test_data_2)
    print(f"Test 2 result: {result}")
    assert result == 67.3
    
    # Test case 3: No utilization data
    test_data_3 = {
        "current": {
            "resources": []
        }
    }
    
    result = collector._extract_gpu_utilization(test_data_3)
    print(f"Test 3 result: {result}")
    assert result == 0.0
    
    print("✓ GPU utilization extraction test passed")


def test_mock_data_processing():
    """Test data processing with mock API responses"""
    print("Testing data processing with mock data...")
    
    # Mock cluster response
    mock_cluster_metrics = {
        "measurements": [
            {
                "type": "TOTAL_GPU",
                "values": [
                    {
                        "timestamp": "2024-01-15T10:30:00Z",
                        "value": 32
                    }
                ]
            },
            {
                "type": "ALLOCATED_GPU", 
                "values": [
                    {
                        "timestamp": "2024-01-15T10:30:00Z",
                        "value": 24
                    }
                ]
            },
            {
                "type": "GPU_UTILIZATION",
                "values": [
                    {
                        "timestamp": "2024-01-15T10:30:00Z",
                        "value": 75.5
                    }
                ]
            }
        ]
    }
    
    # Mock projects response
    mock_projects = [
        {"name": "project-1", "id": "proj-1"},
        {"name": "project-2", "id": "proj-2"}
    ]
    
    # Mock quotas response
    mock_quotas = [
        {
            "name": "project-1",
            "deservedGpus": 8,
            "allocatedGpus": 6
        },
        {
            "name": "project-2", 
            "deservedGpus": 4,
            "allocatedGpus": 2
        }
    ]
    
    # Mock project metrics response
    mock_project_metrics = {
        "current": {
            "resources": [
                {
                    "type": "gpu",
                    "utilization": {
                        "percentage": 80.2
                    }
                }
            ]
        }
    }
    
    # Create client and collector with mocked methods
    client = RunAIAPIClient("https://test.run.ai", "test-token")
    collector = GPUMetricsCollector(client)
    
    # Mock the API calls
    with patch.object(client, 'get_cluster_metrics', return_value=mock_cluster_metrics), \
         patch.object(client, 'get_projects', return_value=mock_projects), \
         patch.object(client, 'get_projects_quotas', return_value=mock_quotas), \
         patch.object(client, 'get_project_metrics', return_value=mock_project_metrics):
        
        # Test cluster metrics collection
        start_time = datetime.now() - timedelta(hours=1)
        end_time = datetime.now()
        
        cluster_metrics = collector.collect_cluster_gpu_metrics(
            cluster_uuid="test-cluster",
            start_time=start_time,
            end_time=end_time
        )
        
        assert cluster_metrics['cluster_uuid'] == "test-cluster"
        assert 'TOTAL_GPU' in cluster_metrics['metrics']
        assert cluster_metrics['metrics']['TOTAL_GPU']['current_value'] == 32
        assert cluster_metrics['metrics']['ALLOCATED_GPU']['current_value'] == 24
        assert cluster_metrics['metrics']['GPU_UTILIZATION']['current_value'] == 75.5
        
        # Test project metrics collection
        project_metrics = collector.collect_project_gpu_metrics(
            cluster_uuid="test-cluster",
            start_time=start_time,
            end_time=end_time
        )
        
        assert len(project_metrics) == 2
        assert project_metrics[0]['project_name'] == "project-1"
        assert project_metrics[0]['gpu_metrics']['gpu_limit'] == 8
        assert project_metrics[0]['gpu_metrics']['gpu_requested'] == 6
        assert project_metrics[0]['gpu_metrics']['gpu_utilization'] == 80.2
    
    print("✓ Mock data processing test passed")


def test_json_output():
    """Test JSON output formatting"""
    print("Testing JSON output formatting...")
    
    # Create sample metrics data
    sample_metrics = {
        "collection_timestamp": datetime.now().isoformat(),
        "time_range": {
            "start": (datetime.now() - timedelta(hours=1)).isoformat(),
            "end": datetime.now().isoformat()
        },
        "clusters": [
            {
                "cluster_uuid": "test-cluster-123",
                "cluster_name": "test-cluster",
                "cluster_level_metrics": {
                    "metrics": {
                        "TOTAL_GPU": {"current_value": 32},
                        "ALLOCATED_GPU": {"current_value": 24},
                        "GPU_UTILIZATION": {"current_value": 75.5}
                    }
                },
                "project_level_metrics": [
                    {
                        "project_name": "test-project",
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
    
    # Test JSON serialization
    try:
        json_output = json.dumps(sample_metrics, indent=2)
        # Verify it can be parsed back
        parsed_data = json.loads(json_output)
        assert parsed_data['clusters'][0]['cluster_uuid'] == "test-cluster-123"
    except Exception as e:
        raise AssertionError(f"JSON serialization failed: {e}")
    
    print("✓ JSON output formatting test passed")


def run_all_tests():
    """Run all test functions"""
    print("Running RunAI GPU Metrics Collector Tests")
    print("=" * 50)
    
    tests = [
        test_api_client_initialization,
        test_metrics_collector_initialization,
        test_gpu_utilization_extraction,
        test_mock_data_processing,
        test_json_output
    ]
    
    passed = 0
    failed = 0
    
    for test_func in tests:
        try:
            test_func()
            passed += 1
        except Exception as e:
            print(f"✗ {test_func.__name__} failed: {e}")
            failed += 1
    
    print("\n" + "=" * 50)
    print(f"Test Results: {passed} passed, {failed} failed")
    
    if failed > 0:
        print("Some tests failed. Please check the implementation.")
        return False
    else:
        print("All tests passed! ✓")
        return True


if __name__ == '__main__':
    success = run_all_tests()
    sys.exit(0 if success else 1)
