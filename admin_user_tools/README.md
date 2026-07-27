# Run:ai Admin User Tools

Scripts for managing Run:ai users and auth. All need `kubectl` access to the cluster, plus `jq` and `curl`.

---

### `create-runai-user.sh`

Creates a local Run:ai user via internal APIs (`kubectl exec`). No API token needed. Auto-detects tenant ID; grants System Administrator by default.

```bash
./create-runai-user.sh                          # auto email + password
./create-runai-user.sh admin@company.com        # set email, auto password
./create-runai-user.sh user@example.com MyPass123
```

### `reset-password.sh`

Resets a local user's Keycloak password and prints a new 16-character password. Useful for password recovery or SSO lockout.

```bash
./reset-password.sh --username test@run.ai
```

### `grant-sysadmin-permission.sh`

Grants System Administrator (tenant scope) to an existing user via the Run:ai API. Prompts for password if omitted.

```bash
./grant-sysadmin-permission.sh --username user@example.com --url https://runai.example.com
```

### `create-runai-api-token.sh`

Pulls admin credentials from Kubernetes secrets and prints a `RUNAI_TOKEN` for API use.

```bash
eval $(./create-runai-api-token.sh | grep RUNAI_TOKEN)
curl -H "Authorization: Bearer $RUNAI_TOKEN" https://runai.example.com/api/v1/projects
```

---

## SSO lockout recovery

```bash
./reset-password.sh --username test@run.ai
./grant-sysadmin-permission.sh --username test@run.ai --url https://runai.example.com
# Then log in and disable SSO auto-redirect in the UI
```

`create-runai-user.sh` and `reset-password.sh` need cluster-admin kubectl (pod exec). `grant-sysadmin-permission.sh` needs valid user credentials instead.
