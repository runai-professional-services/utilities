# Run:ai Admin User Tools

Four tools for managing Run:ai users and authentication, designed for cluster administrators with kubectl access.

---

## `create-runai-user.sh` - Create New Users

Creates new Run:ai local users via internal APIs using kubectl exec. No API token required.

**Usage:** `./create-runai-user.sh [email] [password] [realm] [reset_password] [grant_admin]`

**Examples:**
- `./create-runai-user.sh` - Auto-generate email and password
- `./create-runai-user.sh admin@company.com` - Specify email, auto-generate password
- `./create-runai-user.sh user@example.com MyPass123` - Specify both

**Features:** Auto-detects tenant ID, auto-generates credentials, grants System Administrator permissions (default), displays control plane URL and login page.

**Requirements:** kubectl access to cluster, jq

---

## `reset-password.sh` - Reset User Password

Resets a local user's password via Keycloak and generates a new secure random password.

**Usage:** `./reset-password.sh [--username <email>] [--namespace <ns>] [--url <url>]`

**Example:** `./reset-password.sh --username test@run.ai`

**Features:** Auto-generates secure 16-character password, auto-detects Run:ai URL, verifies new password works.

**Use Case:** Password recovery, SSO lockout scenarios.

**Requirements:** kubectl access to cluster, jq, curl

---

## `grant-sysadmin-permission.sh` - Grant Admin Permissions

Grants System Administrator permissions to an existing user at tenant scope via Run:ai API.

**Usage:** `./grant-sysadmin-permission.sh --username <email> --url <ctrl-plane-url> [--password <pass>]`

**Example:** `./grant-sysadmin-permission.sh --username user@example.com --url https://runai.example.com`

**Features:** Interactive password prompt (if not provided), checks existing permissions before granting, verifies grant succeeded.

**Use Case:** Elevate user permissions, recover from SSO lockout after password reset.

**Requirements:** User credentials (username/password), jq, curl

---

## `create-runai-api-token.sh` - Get API Token

Retrieves admin credentials from Kubernetes and obtains a Run:ai API token.

**Usage:** `./create-runai-api-token.sh`

**Output:** Prints `RUNAI_TOKEN` environment variable for use in API calls.

**Features:** Auto-retrieves admin username/password from Kubernetes secrets, auto-detects control plane URL.

**Use Case:** Scripting, automation, API access.

**Requirements:** kubectl access to cluster, jq, curl

---

## Common Scenarios

### Scenario 1: Create a new admin user
```bash
./create-runai-user.sh admin@company.com
# Outputs: email, password, and login URL
```

### Scenario 2: Recover from SSO lockout
```bash
# Step 1: Reset password
./reset-password.sh --username test@run.ai

# Step 2: Grant admin permissions with new password
./grant-sysadmin-permission.sh --username test@run.ai --url https://runai.example.com

# Step 3: Login and disable SSO auto-redirect in UI
```

### Scenario 3: Get API token for automation
```bash
# Get token and save to variable
eval $(./create-runai-api-token.sh | grep RUNAI_TOKEN)

# Use token in API calls
curl -H "Authorization: Bearer $RUNAI_TOKEN" https://runai.example.com/api/v1/projects
```

### Scenario 4: Quick testing with disposable user
```bash
# Auto-generates everything
./create-runai-user.sh
```

---

## Prerequisites

All tools require:
- kubectl access to the Run:ai cluster
- `jq` - JSON processor (`brew install jq` or `apt-get install jq`)
- `curl` - HTTP client (usually pre-installed)

For `create-runai-user.sh` and `reset-password.sh`: Requires cluster admin access (kubectl exec into pods).

For `grant-sysadmin-permission.sh`: Requires valid user credentials.

For `create-runai-api-token.sh`: Requires kubectl access to read secrets/configmaps.
