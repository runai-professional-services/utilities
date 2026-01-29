# Run:ai Admin User Password Reset Tool

This tool automates the process of resetting a Run:ai local admin user password via Keycloak when a user is locked out due to SSO auto-redirect issues or forgotten passwords. The tool automatically generates a secure random password and displays it after the reset is complete.

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

## Support

For issues or questions, please contact Run:ai support.
