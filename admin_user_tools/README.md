# Run:ai Admin User Password Reset Tools

This directory contains two tools to help recover from SSO lockout scenarios:

1. **`reset_password.sh`** - Resets a local user's password via Keycloak
2. **`grant_sysadmin_permission.sh`** - Grants System administrator permissions to a user

## Quick Start - SSO Lockout Recovery

If you're locked out due to SSO auto-redirect:

```bash
# Step 1: Reset password (requires kubectl access)
./reset_password.sh --username test@run.ai

# Step 2: Grant admin permissions using the new password
./grant_sysadmin_permission.sh --username test@run.ai --url https://runai.example.com
# Enter the password from Step 1 when prompted

# Step 3: Disable SSO auto-redirect (see examples below)
```

---

# Password Reset Tool (`reset_password.sh`)

This tool automates the process of resetting a Run:ai local user password via Keycloak when a user is locked out due to SSO auto-redirect issues or forgotten passwords. The tool automatically generates a secure random password and displays it after the reset is complete.

## Use Case

This is particularly useful when:
- SSO auto-redirect is enabled and the SSO user doesn't have proper Access Rules configured
- A local admin password is forgotten
- You need to regain access to the Run:ai UI through a local admin account

## Prerequisites

- `kubectl` access to the Run:ai Kubernetes cluster
- `jq` command-line JSON processor
- `curl` command-line tool
- Proper KUBECONFIG set to access the cluster

## Usage

### Basic Usage

```bash
# Reset password for default user (test@run.ai)
./reset_password.sh

# Reset password for a specific user
./reset_password.sh --username <USERNAME>
```

### With All Options

```bash
./reset_password.sh \
  --username test@run.ai \
  --namespace runai-backend \
  --url https://runai.example.com
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `--username` | No | `test@run.ai` | Username to reset password for (e.g., `test@run.ai`) |
| `--namespace` | No | `runai-backend` | Kubernetes namespace where Run:ai is installed |
| `--url` | No | Auto-detected | Run:ai control plane URL (e.g., `https://runai.example.com`) |

## Password Generation

The tool automatically generates a secure random password that meets the following requirements:
- 16 characters long
- At least 1 digit (0-9)
- At least 1 lowercase letter (a-z)
- At least 1 uppercase letter (A-Z)
- At least 1 special character (!, @, #, $, etc.)

The generated password is displayed at the end of the script. You should change it to a more personal password within the Run:ai UI after logging in.

## Examples

### Example 1: Reset test@run.ai password (auto-detect URL)

```bash
./reset_password.sh
```

### Example 2: Reset with custom URL

```bash
./reset_password.sh --url https://runai-qa.cegedim.cloud
```

### Example 3: Reset for different user

```bash
./reset_password.sh --username support@company.com
```

## How It Works

The script performs the following steps:

1. **Retrieves Keycloak admin credentials** from the Kubernetes secret `runai-backend-keycloakx`
2. **Auto-detects Run:ai URL** from the configmap `runai-backend-tenants-manager` (if not provided)
3. **Obtains Keycloak admin token** using the retrieved credentials
4. **Finds the target user** in Keycloak by username
5. **Resets the password** using Keycloak Admin API
6. **Verifies the new password** by obtaining a Run:ai API token

## Output

The script provides colored output:
- ✓ Green: Success messages
- ✗ Red: Error messages
- ℹ Yellow: Info messages

Example output:

```
==========================================
Run:ai Admin Password Reset Tool
==========================================

ℹ Target username: test@run.ai
ℹ Namespace: runai-backend
ℹ Generating secure random password...

ℹ Step 1: Retrieving Keycloak admin credentials from Kubernetes...
✓ Keycloak admin credentials retrieved

ℹ Step 2: Auto-detecting Run:ai control plane URL...
✓ Run:ai URL detected: https://runai.example.com

ℹ Step 3: Obtaining Keycloak admin token...
✓ Keycloak admin token obtained

ℹ Step 4: Finding user 'test@run.ai' in Keycloak...
✓ User found (ID: c7053420-5e28-4af9-b571-e590f676d6c7)

ℹ Step 5: Resetting password for user 'test@run.ai'...
✓ Password reset successfully

ℹ Step 6: Verifying new password by obtaining Run:ai API token...
✓ New password verified successfully

==========================================
✓ Password reset completed successfully!
==========================================

Login Credentials:
  Username: test@run.ai
  Password: Xy7@kLm3pQ9#vR2z

Run:ai URL: https://runai.example.com

ℹ IMPORTANT: This is a randomly generated password.
ℹ Please login and change it to a more personal password in the UI.
ℹ Go to: User Settings → Change Password
```

## Troubleshooting

### Error: "kubectl is not installed or not in PATH"
Install kubectl and ensure it's in your PATH.

### Error: "jq is not installed or not in PATH"
Install jq: `brew install jq` (macOS) or `apt-get install jq` (Ubuntu/Debian)

### Error: "Failed to retrieve Keycloak admin credentials"
- Ensure you have kubectl access to the cluster
- Verify the namespace is correct (default: `runai-backend`)
- Check that the secret `runai-backend-keycloakx` exists

### Error: "User not found in Keycloak"
- Verify the username is correct (default is `test@run.ai`)
- The username should be the full email address format
- Check that the user exists in the Run:ai realm in Keycloak

### Error: "Failed to verify new password"
- The password was reset successfully, but verification failed
- Try logging in manually to the Run:ai UI
- Check that the Run:ai control plane is accessible

## Related Use Case: Disable SSO Auto-Redirect

After resetting the password, if you need to disable SSO auto-redirect, you can use the reset admin credentials:

```bash
# Get a Run:ai API token (use the generated password from the script output)
RUNAI_TOKEN=$(curl -s -X POST "https://runai.example.com/api/v1/token" \
  -H "Content-Type: application/json" \
  -d '{"grantType":"password","clientID":"cli","username":"test@run.ai","password":"<GENERATED_PASSWORD>"}' \
  | jq -r .accessToken)

# Disable SSO auto-redirect (replace 'oidc' with your IDP type: oidc, saml, or openshift-v4)
curl "https://runai.example.com/api/v1/security/settings/autoRedirectSSO" \
  -X PUT \
  -H "Authorization: Bearer $RUNAI_TOKEN" \
  -H "Content-Type: application/json" \
  --data-raw '{"enabled":false,"idpAlias":"oidc"}'
```

## Security Notes

- This tool requires cluster admin access to retrieve Keycloak credentials
- A secure random password is automatically generated for each reset
- The generated password is displayed only once in the terminal output
- After logging in, change the password to something more memorable in the Run:ai UI (User Settings → Change Password)

---

# Grant System Administrator Permission Tool (`grant_sysadmin_permission.sh`)

This tool grants System administrator permissions to a Run:ai local user at tenant scope. It's particularly useful when a user needs admin permissions to disable SSO auto-redirect or manage other security settings.

## Use Case

This tool is designed for scenarios where:
- A user has been locked out due to SSO auto-redirect and needs admin permissions to disable it
- You need to grant admin permissions to a local user account
- A user needs to manage security settings, access rules, or other admin functions

## Prerequisites

- User's username and password
- Run:ai Control Plane URL
- `curl` command-line tool
- `jq` command-line JSON processor

## Usage

### Interactive Password Input (Recommended)

```bash
./grant_sysadmin_permission.sh --username <USERNAME> --url <CTRL_PLANE_URL>
```

The script will prompt for the password interactively, which is safer for passwords with special characters.

### Password as Argument

```bash
./grant_sysadmin_permission.sh \
  --username <USERNAME> \
  --url <CTRL_PLANE_URL> \
  --password '<PASSWORD>'
```

### Using Environment Variable

```bash
export USER_PASSWORD='MySecurePass123!'
./grant_sysadmin_permission.sh \
  --username test@run.ai \
  --url https://runai.example.com \
  --password "$USER_PASSWORD"
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--username` | Yes | Username to grant admin permissions (e.g., `test@run.ai`) |
| `--url` | Yes | Run:ai control plane URL (e.g., `https://runai.example.com`) |
| `--password` | No | User's password (will prompt if not provided) |

## Examples

### Example 1: Interactive password (recommended for special characters)

```bash
./grant_sysadmin_permission.sh \
  --username test@run.ai \
  --url https://runai-qa.cegedim.cloud
```

The script will prompt: `Enter password for test@run.ai:`

### Example 2: Password as argument

```bash
./grant_sysadmin_permission.sh \
  --username test@run.ai \
  --url https://runai.example.com \
  --password 'MyPassword123!'
```

### Example 3: Using environment variable

```bash
export USER_PASSWORD='Complex@Pass#123'
./grant_sysadmin_permission.sh \
  --username admin@company.com \
  --url https://runai.company.com \
  --password "$USER_PASSWORD"
```

## How It Works

The script performs the following steps:

1. **Obtains API Token**: Authenticates the user and gets a Run:ai API token
2. **Finds System Administrator Role**: Retrieves the role ID for "System administrator"
3. **Extracts Tenant ID**: Gets the tenant ID from the JWT token
4. **Checks Existing Permissions**: Verifies if the user already has System administrator role at tenant scope
5. **Grants Permission** (if needed): Creates an access rule to grant System administrator role
6. **Verifies Success**: Confirms the permission was added successfully

## Output

### Example Output (User Already Has Permission)

```
==========================================
Grant Admin Permission Tool
==========================================

ℹ Target username: test@run.ai
ℹ Control Plane URL: https://runai.example.com

ℹ Step 1: Obtaining Run:ai API token...
✓ API token obtained

ℹ Step 2: Finding System administrator role ID...
✓ System administrator role ID: 13

ℹ Step 3: Extracting Tenant ID from JWT token...
✓ Tenant ID: 1001

ℹ Step 4: Checking existing permissions for test@run.ai...
✓ User already has System administrator role at tenant scope - no action needed

==========================================
✓ Task completed - user already has admin permissions
==========================================
```

### Example Output (Permission Granted)

```
==========================================
Grant Admin Permission Tool
==========================================

ℹ Target username: test@run.ai
ℹ Control Plane URL: https://runai.example.com

ℹ Step 1: Obtaining Run:ai API token...
✓ API token obtained

ℹ Step 2: Finding System administrator role ID...
✓ System administrator role ID: 13

ℹ Step 3: Extracting Tenant ID from JWT token...
✓ Tenant ID: 1001

ℹ Step 4: Checking existing permissions for test@run.ai...
ℹ User does not have System administrator role at tenant scope

ℹ Step 5: Granting System administrator permission to test@run.ai...
✓ System administrator permission granted successfully

ℹ Step 6: Verifying permission was added...
✓ Verified: System administrator permission is active

==========================================
✓ System administrator permission granted successfully!
==========================================

User test@run.ai now has System administrator role at tenant scope.
They can now:
  - Access all Run:ai features
  - Manage users and access rules
  - Configure SSO and security settings

Control Plane URL: https://runai.example.com
```

## Troubleshooting

### Error: "Failed to obtain API token"
- Verify the username and password are correct
- Check that the Control Plane URL is accessible
- Ensure the user account exists in Run:ai

### Error: "Failed to find System administrator role"
- The System administrator role should exist by default
- Contact Run:ai support if this role is missing

### Error: "Failed to extract Tenant ID from JWT token"
- This usually indicates an authentication issue
- Verify the user account is valid
- Check that the user belongs to a tenant

### Error: "Failed to grant System administrator permission"
- The user may not have sufficient permissions to create access rules
- You may need to use a different admin account first
- Check the response body for specific error details

## Security Notes

- Passwords are handled securely through command-line arguments or interactive prompts
- Use single quotes around passwords to avoid shell interpretation of special characters
- Interactive password input (no `--password` flag) is recommended for better security
- Passwords are not logged or stored by the script

---

## Complete SSO Lockout Recovery Workflow

When a user is locked out due to SSO auto-redirect:

### Step 1: Reset Password

```bash
./reset_password.sh --username test@run.ai
```

Output will show:
```
Login Credentials:
  Username: test@run.ai
  Password: xY9#mK2&pL4@nR7
```

### Step 2: Grant Admin Permissions

```bash
./grant_sysadmin_permission.sh \
  --username test@run.ai \
  --url https://runai-qa.cegedim.cloud
# Enter the password from Step 1 when prompted
```

### Step 3: Disable SSO Auto-Redirect

```bash
# Get the tenant ID and password from previous steps
CTRL_PLANE_URL="https://runai-qa.cegedim.cloud"
USERNAME="test@run.ai"
PASSWORD="<password-from-step-1>"

# Get API token
TOKEN=$(curl -s -X POST "$CTRL_PLANE_URL/api/v1/token" \
  -H "Content-Type: application/json" \
  -d "{\"grantType\":\"password\",\"clientID\":\"cli\",\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" \
  | jq -r .accessToken)

# Check IDP type
curl -s "$CTRL_PLANE_URL/api/v1/idps" -H "Authorization: Bearer $TOKEN" | jq '.[].alias'

# Disable auto-redirect (replace 'oidc' with your IDP alias: oidc, saml, or openshift-v4)
curl "$CTRL_PLANE_URL/api/v1/security/settings/autoRedirectSSO" \
  -X PUT \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data-raw '{"enabled":false,"idpAlias":"oidc"}'
```

### Step 4: Access the UI

1. Navigate to your Run:ai URL
2. You'll see the login page (no auto-redirect!)
3. Login with the username and password from Step 1
4. Go to **Settings → Security → Access Rules** and configure your SSO user
5. Optionally re-enable SSO auto-redirect from **Settings → General → Authentication**

## Support

For issues or questions, please contact Run:ai support.
