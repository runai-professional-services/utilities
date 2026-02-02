# Run:ai Admin User Tools

This directory contains three tools for managing Run:ai users:

1. **`create-runai-user.sh`** - Creates new local users with optional System administrator permissions
2. **`reset_password.sh`** - Resets a local user's password via Keycloak
3. **`grant_sysadmin_permission.sh`** - Grants System administrator permissions to a user

## Quick Start - Create New User

```bash
# Create a user with auto-generated email and password
./create-runai-user.sh

# Create a new user with System administrator permissions (auto-detects tenant)
./create-runai-user.sh newuser@example.com

# Create user with custom password (email specified, password auto-generated)
./create-runai-user.sh newuser@example.com

# Create user with both email and password specified
./create-runai-user.sh newuser@example.com MySecurePass123!

# Create user without admin permissions
./create-runai-user.sh newuser@example.com MyPass123 runai false false
```

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

# User Creation Tool (`create-runai-user.sh`)

This tool automates the process of creating new Run:ai local users via the internal APIs, mimicking the exact same flow as the Run:ai UI. It creates users in Keycloak and optionally grants them System administrator permissions scoped to the entire tenant.

## Use Cases

This tool is useful when:
- You need to create local admin users without accessing the UI
- You want to automate user provisioning via kubectl
- You need to quickly create users with System administrator permissions
- You want to bootstrap admin access to a new Run:ai installation
- **Testing/Demo environments**: Auto-generate disposable users with random credentials
- **Automated provisioning**: Integrate into scripts where credentials can be auto-generated and stored
- **Quick user creation**: No need to think of email/password combinations for temporary users

## Prerequisites

- `kubectl` access to the Run:ai Kubernetes cluster
- `jq` command-line JSON processor
- `curl` command-line tool (available in the identity-manager pod)
- Proper KUBECONFIG set to access the cluster

## Usage

### Basic Usage

```bash
# Create user with auto-generated email and password
./create-runai-user.sh

# Create user with specified email (password auto-generated)
./create-runai-user.sh newuser@example.com

# Create user with both email and password specified
./create-runai-user.sh newuser@example.com MySecurePass123!
```

### Advanced Options

```bash
# Full syntax
./create-runai-user.sh [email] [password] [realm] [reset_password] [grant_admin]

# Create user without admin permissions
./create-runai-user.sh user@example.com MyPass123 runai false false

# Create user with temporary password (requires reset on first login)
./create-runai-user.sh user@example.com TempPass123 runai true true

# Auto-generate everything for testing
./create-runai-user.sh
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `email` | No | Auto-generated | Email address for the new user (format: `user-<random>-<timestamp>@runai.local`) |
| `password` | No | Auto-generated | User password (16 chars with mixed case, digits, special chars) |
| `realm` | No | `runai` | Keycloak realm / tenant name |
| `reset_password` | No | `true` | Force password reset on first login |
| `grant_admin` | No | `true` | Grant System Administrator role at tenant scope |

## Examples

### Example 1: Auto-generate everything (testing/demo)

```bash
./create-runai-user.sh
```

This will:
- Auto-generate a random email like `user-a8f3k9d2-1738518400@runai.local`
- Auto-generate a secure 16-character password
- Grant System Administrator permissions (tenant-wide)
- Auto-detect the tenant ID from the realm
- Display the generated credentials in the output

**Use case:** Quick testing, demo environments, or automated provisioning

### Example 2: Specify email, auto-generate password

```bash
./create-runai-user.sh admin@company.com
```

This will:
- Create user with email `admin@company.com`
- Auto-generate a secure random password
- Require password reset on first login
- Grant System Administrator permissions (tenant-wide)
- Auto-detect the tenant ID from the realm

### Example 3: Create user with custom password

```bash
./create-runai-user.sh user@example.com "MySecurePass#123"
```

### Example 4: Create user without admin permissions

```bash
./create-runai-user.sh viewer@example.com ViewPass123 runai false false
```

## How It Works

The script performs the following steps:

1. **Generates Credentials** (if not provided): 
   - Auto-generates random email in format `user-<random>-<timestamp>@runai.local`
   - Auto-generates secure 16-character password with mixed case, digits, and special characters
2. **Auto-detects Tenant ID**: Queries the `/internal/api/v1/tenants` API to find the tenant ID for the specified realm
3. **Creates User in Keycloak**: Calls `/internal/users` API to create the user with the email, password, and realm
4. **Grants System Administrator** (if enabled): Calls `/internal/authorization/access-rules` API to create an access rule granting System administrator role at tenant scope
5. **Verifies Permissions**: Queries `/internal/authorization/subject-access-rules` to confirm the permissions were created successfully

All steps use **internal APIs** that don't require authentication when called from within the cluster via `kubectl exec`.

## Output

### Example Output (Auto-Generated Credentials)

```
ℹ No email provided - generated random email: user-k7m9p4x2-1738518400@runai.local

ℹ No password provided - generated secure random password

========================================
Run:AI User Creation Script
========================================

Configuration:
  Email:          user-k7m9p4x2-1738518400@runai.local (auto-generated)
  Password:       7Kp**** (auto-generated)
  Realm:          runai
  Reset Password: true
  Grant Admin:    true

Testing cluster connectivity...
✓ Cluster connectivity OK

Finding required pods...
✓ Identity-manager pod: identity-manager-abc123
✓ Authorization pod: authorization-xyz789
✓ Tenants-manager pod: tenants-manager-def456

Auto-detecting tenant ID from realm 'runai'...
✓ Tenant ID detected: 1004

========================================
Creating User
========================================
Response: {"id":"a1b2c3d4-e5f6-7890-abcd-ef1234567890"}

✓ User created successfully in Keycloak

========================================
Step 2: Granting System Administrator Access
========================================
Response: {"id":15}

✓ Access rule creation API returned success

Verifying permissions...
User's access rules:
  - Role: System administrator, Scope: tenant (runai)

✓ System Administrator permissions created!

The user now has tenant-wide System Administrator access for:
  - Run:AI UI
  - Run:AI API
  - CLI operations

========================================
✓ User Created Successfully!
========================================

User Details:
  Email:              user-k7m9p4x2-1738518400@runai.local
  Password:           7Kp#mN9@xR2&qL5
  Realm:              runai
  Reset Password:     true
  Role:               System Administrator (Tenant-wide)
  Tenant ID:          1004

Important:
  • Email was auto-generated - save these credentials!
  • Password was auto-generated - save it securely!
  • User will be prompted to change password on first login

User can now login to Run:AI!
```

### Example Output (Specified Email)

```
========================================
Run:AI User Creation Script
========================================

Configuration:
  Email:          admin@company.com
  Password:       Tem****
  Realm:          runai
  Reset Password: true
  Grant Admin:    true

Testing cluster connectivity...
✓ Cluster connectivity OK

Finding required pods...
✓ Identity-manager pod: identity-manager-abc123
✓ Authorization pod: authorization-xyz789
✓ Tenants-manager pod: tenants-manager-def456

Auto-detecting tenant ID from realm 'runai'...
✓ Tenant ID detected: 1004

========================================
Creating User
========================================
Response: {"id":"a1b2c3d4-e5f6-7890-abcd-ef1234567890"}

✓ User created successfully in Keycloak

========================================
Step 2: Granting System Administrator Access
========================================
Response: {"id":15}

✓ Access rule creation API returned success

Verifying permissions...
User's access rules:
  - Role: System administrator, Scope: tenant (runai)

✓ System Administrator permissions created!

The user now has tenant-wide System Administrator access for:
  - Run:AI UI
  - Run:AI API
  - CLI operations

========================================
✓ User Created Successfully!
========================================

User Details:
  Email:              admin@company.com
  Password:           TempPassword123!
  Realm:              runai
  Reset Password:     true
  Role:               System Administrator (Tenant-wide)
  Tenant ID:          1004

Important:
  • The user will be prompted to change their password on first login

User can now login to Run:AI!
```

## Troubleshooting

### Error: "Cannot connect to cluster or namespace runai-backend does not exist"
- Ensure you have kubectl access to the cluster
- Verify your KUBECONFIG is set correctly
- Check that Run:ai is installed in the `runai-backend` namespace

### Error: "Identity-manager pod not found"
- Verify Run:ai is properly installed
- Check that the control plane components are running: `kubectl get pods -n runai-backend`

### Error: "Could not auto-detect tenant ID"
- Verify the realm name is correct (default: `runai`)
- Check that the tenants-manager service is running
- Manually check tenants: `kubectl exec -n runai-backend <tenants-pod> -- curl -s http://localhost:8080/internal/api/v1/tenants`

### Error: "User already exists in Keycloak"
- The user email is already registered
- Use the `reset_password.sh` tool to reset the existing user's password
- Use the `grant_sysadmin_permission.sh` tool to grant admin permissions if needed

### Warning: "Access rule creation failed"
- The user was created but permissions were not granted
- Use the `grant_sysadmin_permission.sh` tool to manually grant admin permissions
- Check that the authorization service is running properly

## Security Notes

- This tool requires cluster admin access to execute commands in pods
- **Auto-generated credentials** are displayed in the output - save them immediately as they won't be shown again
- Passwords are displayed in the output - use secure channels when sharing credentials
- Auto-generated passwords are cryptographically secure (16 chars with mixed case, digits, special chars)
- Users created with `reset_password: true` (default) must change their password on first login
- System Administrator role grants full access to all Run:ai features at the tenant level
- Auto-generated emails use the format `user-<random>-<timestamp>@runai.local` for easy identification

## What This Tool Creates

The tool mimics the exact same flow as the Run:ai UI and creates:

1. **User in Keycloak** (identity/authentication layer)
   - Email/username
   - Password (temporary or permanent)
   - Enabled status

2. **Access Rule in Authorization Database** (permissions layer)
   - Subject: user email
   - Role: System administrator (roleId: 1)
   - Scope: tenant-wide (scopeType: tenant, scopeId: auto-detected)
   - Automatically syncs to cluster via Run:ai controllers

The user will have full access to:
- ✅ Run:AI UI - all features and settings
- ✅ Run:AI API - full API access
- ✅ CLI operations - runai CLI with admin privileges
- ✅ Workload management - create, modify, delete workloads
- ✅ User management - create users, manage access rules
- ✅ Security settings - configure SSO, authentication, etc.

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
