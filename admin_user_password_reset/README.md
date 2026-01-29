# Run:ai Admin User Password Reset Tool

This tool automates the process of resetting a Run:ai local admin user password via Keycloak when a user is locked out due to SSO auto-redirect issues or forgotten passwords.

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
./reset_password.sh --username <USERNAME> --password <NEW_PASSWORD>
```

### With All Options

```bash
./reset_password.sh \
  --username admin@run.ai \
  --password 'MyNewPass123!' \
  --namespace runai-backend \
  --url https://runai.example.com
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `--username` | Yes | - | Username to reset password for (e.g., `admin@run.ai`) |
| `--password` | Yes | - | New password (must meet complexity requirements) |
| `--namespace` | No | `runai-backend` | Kubernetes namespace where Run:ai is installed |
| `--url` | No | Auto-detected | Run:ai control plane URL (e.g., `https://runai.example.com`) |

## Password Requirements

The new password must meet the following requirements:
- At least 8 characters long
- At least 1 digit (0-9)
- At least 1 lowercase letter (a-z)
- At least 1 uppercase letter (A-Z)
- At least 1 special character (!, @, #, $, etc.)

## Examples

### Example 1: Reset admin@run.ai password (auto-detect URL)

```bash
./reset_password.sh --username admin@run.ai --password 'SecurePass123!'
```

### Example 2: Reset with custom URL

```bash
./reset_password.sh \
  --username admin@run.ai \
  --password 'SecurePass123!' \
  --url https://runai-qa.cegedim.cloud
```

### Example 3: Reset for different user

```bash
./reset_password.sh --username support@company.com --password 'NewPassword456#'
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

ℹ Target username: admin@run.ai
ℹ Namespace: runai-backend

ℹ Step 1: Retrieving Keycloak admin credentials from Kubernetes...
✓ Keycloak admin credentials retrieved

ℹ Step 2: Auto-detecting Run:ai control plane URL...
✓ Run:ai URL detected: https://runai.example.com

ℹ Step 3: Obtaining Keycloak admin token...
✓ Keycloak admin token obtained

ℹ Step 4: Finding user 'admin@run.ai' in Keycloak...
✓ User found (ID: c7053420-5e28-4af9-b571-e590f676d6c7)

ℹ Step 5: Resetting password for user 'admin@run.ai'...
✓ Password reset successfully

ℹ Step 6: Verifying new password by obtaining Run:ai API token...
✓ New password verified successfully

==========================================
✓ Password reset completed successfully!
==========================================

You can now login to Run:ai with:
  Username: admin@run.ai
  Password: (the password you provided)

Run:ai URL: https://runai.example.com
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
- Verify the username is correct
- The username should be the full email address (e.g., `admin@run.ai`)
- Check that the user exists in the Run:ai realm in Keycloak

### Error: "Failed to verify new password"
- The password was reset successfully, but verification failed
- Try logging in manually to the Run:ai UI
- Check that the Run:ai control plane is accessible

## Related Use Case: Disable SSO Auto-Redirect

After resetting the password, if you need to disable SSO auto-redirect, you can use the reset admin credentials:

```bash
# Get a Run:ai API token
RUNAI_TOKEN=$(curl -s -X POST "https://runai.example.com/api/v1/token" \
  -H "Content-Type: application/json" \
  -d '{"grantType":"password","clientID":"cli","username":"admin@run.ai","password":"YourNewPassword"}' \
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
- Passwords are passed as command-line arguments (not logged but visible in process list)
- Use single quotes around passwords to avoid shell interpretation of special characters
- Always use strong passwords that meet the complexity requirements

## Support

For issues or questions, please contact Run:ai support.
