# Policy Templates

This directory contains YAML templates for RunAI policies that are loaded dynamically by the policy script.

## Running the Script

1. Load environment variables from the `values.env` file:
   ```bash
   export $(cat values.env | xargs)
   ```

2. Run the Python script:
   ```bash
   python start.py
   ```

The `export $(cat values.env | xargs)` command loads all environment variables defined in the `values.env` file into the current shell session, making them available to the Python script.

## Template Files

The script automatically loads these templates from the current directory where the script is executed. The template files must be placed in the same directory as the `start.py` script.

- `policy_template_standard.yaml`
Template for standard policies (trainings, workspaces, inferences).

- `policy_template_distributed.yaml`
Template for distributed training policies. This template differs from the standard template as it includes separate configurations for master and workers.

The templates use standard YAML format with `PLACEHOLDER_NAME` placeholders. The script uses simple string replacement for variable substitution.

- `PROJECT_ID_PLACEHOLDER` - The project ID (integer)
- `PROJECT_NAME_PLACEHOLDER` - The project name (string)
- `USER_HOME_DIR_PLACEHOLDER` - The user's home directory path (string)
- `TYPE_POLICY_PLACEHOLDER` - The policy type (trainings, workspaces, distributed, inferences)

### CSV File Structure

The `project_list.csv` file should contain the following columns:

| Column | Description | Example |
|--------|-------------|---------|
| project_id | The project ID (integer) | 123 |
| project_name | The project name (string) | "My Project" |
| user_home_dir | The user's home directory path (string) | "/home/username" |

**Example CSV content:**
```csv
project_id,project_name,user_home_dir
123,Project A,/home/user1
456,Project B,/home/user2
789,Project C,/home/user3
```

**Note:** The first row should be a header row with column names. The script will skip this header row when processing the data.

### Environment Variables (values.env)

The `values.env` file contains environment variables required for the script to authenticate and connect to the RunAI cluster. You must configure these variables before running the script:

| Variable | Description | Required |
|----------|-------------|----------|
| `RUN_AI_APP_CLIENT_ID` | RunAI application client ID for authentication | Yes |
| `RUN_AI_APP_CLIENT_SECRET` | RunAI application client secret for authentication | Yes |
| `RUN_AI_CLUSTER_ID` | The RunAI cluster ID to connect to | Yes |
| `RUN_AI_BASE_URL` | The RunAI control plane URL | Yes |

**Security Note:** Keep your `values.env` file secure and never commit it to version control. Consider adding it to your `.gitignore` file to prevent accidental commits.
