# Custom RBAC Utility

A Python script to automate the creation and testing of custom RBAC roles in Run:ai.

## Overview

This utility enables and configures custom Role-Based Access Control (RBAC) roles in Run:ai environments. It combines permissions from multiple predefined roles to create comprehensive custom roles for testing and deployment scenarios.

## Features

- **Enable Custom RBAC**: Automatically enables the custom roles feature flag
- **Role Creation**: Creates custom roles by combining permissions from multiple predefined roles
- **Permission Merging**: Intelligently merges and deduplicates permissions from different roles
- **Role Assignment**: Assigns custom roles to users for testing
- **Error Handling**: Robust error handling with detailed feedback and recovery options

## Prerequisites

- Python 3.x with `requests` library
- Run:ai system administrator credentials
- Access to Run:ai Control Plane API

## Configuration

Set credentials via environment variables (recommended) or update variables in `start.py`:

```bash
export RUNAI_CTRL_PLANE_URL="https://your-runai-instance.com"
export RUNAI_USERNAME="your-admin-username"
export RUNAI_PASSWORD="your-admin-password"
export TARGET_USER_EMAIL="user@example.com"  # Email of user to assign role to
```

## Usage

```bash
python3 start.py
```

The script will:
1. Validate configuration and authenticate
2. Enable the custom RBAC feature flag
3. Fetch permissions from predefined roles (Credentials admin, Data source admin, Environment admin, L2 researcher, ML engineer, Template admin)
4. Create a combined custom role with merged permissions
5. Assign the role to the specified user email (or tenant UUID if no email provided)

## What It Does

The script combines permissions from these predefined roles:
- **Role 10**: Credentials administrator
- **Role 11**: Data source administrator  
- **Role 9**: Environment administrator
- **Role 8**: L2 researcher
- **Role 6**: ML engineer
- **Role 13**: Template administrator

It creates a new custom role with all unique permissions merged together, suitable for comprehensive testing scenarios.

## API Endpoints Used

- `POST /api/v1/token` - Authentication
- `GET /api/v1/tenants` - Tenant information
- `PUT /v1/k8s/setting` - Enable feature flag
- `GET/POST /api/v2/authorization/roles` - Role management
- `POST /api/v1/access-rules` - Role assignment

## Output

The script provides detailed output including:
- Configuration validation results
- Role creation status with error recovery
- Permission breakdown and assignment results
- Next steps for manual testing

Perfect for Customer Success and Support teams to quickly set up robust custom RBAC testing environments.
