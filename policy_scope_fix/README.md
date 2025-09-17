# RunAI Policy Scope Fix

A utility script to detect and fix RunAI policies that are missing required scope labels.

## Overview

This script addresses issues where RunAI policies (inference, training, interactive, and distributed policies) are missing proper scope labels, which can cause "Unable to identify relevant scope" errors and cluster-sync problems.

## Features

- **Audit Mode (Default)**: Scans all RunAI policies and reports which ones are missing scope labels
- **Fix Mode**: Automatically adds appropriate scope labels to policies that are missing them
- **Smart Scope Detection**: Determines the correct scope (project, department, or cluster) based on namespace location and available metadata
- **Comprehensive Reporting**: Provides detailed statistics and actionable results

## Usage

### Audit Mode (Default)
```bash
./start.sh
# or explicitly
./start.sh --dry-run
```

### Fix Mode
```bash
./start.sh --fix
```

## How It Works

1. **Discovers RunAI Namespaces**: Finds all namespaces with the `runai/queue` label
2. **Scans Policies**: Examines all RunAI policy types in each namespace
3. **Checks Scope Labels**: Identifies policies missing required scope labels:
   - `run.ai/project` (for project-scoped policies)
   - `run.ai/department` (for department-scoped policies)
   - `run.ai/cluster-wide` (for cluster-wide policies)
   - `run.ai/tenant-wide` (for tenant-wide policies)
4. **Applies Fixes**: In fix mode, automatically adds appropriate scope labels based on:
   - Policies in project namespaces → project scope
   - Policies in `runai` namespace → department or cluster scope

## Prerequisites

- `kubectl` configured with access to the RunAI cluster
- Appropriate permissions to read and modify RunAI policies
- Bash shell environment

## Output

The script provides:
- List of policies with existing scope labels (✅)
- List of policies missing scope labels (❌)
- Total statistics and fix results
- Actionable next steps

## Policy Types Supported

- InferencePolicy
- TrainingPolicy
- InteractivePolicy
- DistributedPolicy

## Error Handling

- Continues processing even if individual policies fail
- Reports failed fixes separately
- Uses `set -euo pipefail` for robust error handling
