# Policy Templates

This directory contains YAML templates for RunAI policies that are loaded dynamically by the policy script.

## Template Files

### `policy_template_distributed.yaml`
Template for distributed training policies. This template includes separate configurations for master and worker nodes.

### `policy_template_standard.yaml`
Template for standard policies (trainings, workspaces, inferences). This template includes hostPath mounts for `/etc/passwd` and `/etc/group`.

## Template Variables

The following placeholders can be used in the templates and will be replaced with actual values:

- `PROJECT_ID_PLACEHOLDER` - The project ID (integer)
- `PROJECT_NAME_PLACEHOLDER` - The project name (string)
- `USER_HOME_DIR_PLACEHOLDER` - The user's home directory path (string)
- `TYPE_POLICY_PLACEHOLDER` - The policy type (trainings, workspaces, distributed, inferences)

## Usage

The script automatically loads these templates from the current directory where the script is executed. The template files must be placed in the same directory as the `start.py` script.

Required template files:
- `policy_template_distributed.yaml`
- `policy_template_standard.yaml`

Required data file:
- `project_list.csv` - CSV file containing project information

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

### Running the Script

1. Load environment variables from the `values.env` file:
   ```bash
   export $(cat values.env | xargs)
   ```

2. Run the Python script:
   ```bash
   python start.py
   ```

The `export $(cat values.env | xargs)` command loads all environment variables defined in the `values.env` file into the current shell session, making them available to the Python script.

## Template Format

Templates use standard YAML format with `PLACEHOLDER_NAME` placeholders. The script uses simple string replacement for variable substitution.

Example:
```yaml
meta:
  scope: project
  projectId: PROJECT_ID_PLACEHOLDER
  name: PROJECT_NAME_PLACEHOLDER-TYPE_POLICY_PLACEHOLDER
```

## Adding New Templates

To add a new template:

1. Create a new YAML file in the current directory with the naming convention `policy_template_[type].yaml`
2. Use the appropriate placeholders for dynamic values
3. Update the script's `load_templates()` method to load your new template
4. Update the `put_policy()` method to use your new template for the appropriate policy type 