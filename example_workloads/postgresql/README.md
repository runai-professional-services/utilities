# PostgreSQL Database as RunAI Workload

> **⚠️ DISCLAIMER**: RunAI workloads are not intended for running production database instances like PostgreSQL. This is **not a best practice** for database deployment. Databases should typically be deployed using dedicated database services, operators, or stateful workload management systems. This example is provided for educational, testing, or development purposes only. **Proceed at your own risk** and do not use this approach for production workloads.

This folder contains examples and instructions for running a PostgreSQL database as a RunAI workload. It provides two deployment approaches: declarative YAML configuration and CLI commands.

**Prerequisites**: This example assumes you are working with the RunAI project `mockdb`, which uses the corresponding namespace `runai-mockdb`.


## Overview

This setup demonstrates how to:
- Deploy a PostgreSQL database as a RunAI Interactive Workload
- Configure persistent storage for database data
- Set up database initialization with users and sample data
- Deploy pgAdmin as a GUI tool for database management and testing
- Test database connectivity and permissions

## Deployment Options

### Option 1: Declarative YAML Approach

Deploy using the provided YAML files in the following order:

1. **Create the secret** (contains database passwords):
   ```bash
   kubectl apply -f runai-secret.yaml
   ```

2. **Create the persistent volume claim** (for database storage):
   ```bash
   kubectl apply -f runai-pvc.yaml
   ```

3. **Create the ConfigMap** (contains database initialization script):
   ```bash
   kubectl apply -f runai-cm.yaml
   ```

4. **Deploy the PostgreSQL workload**:
   ```bash
   kubectl apply -f runai-iw.yaml
   ```

### Option 2: CLI Command Approach

**Note**: You must first create the prerequisite resources (PVC, Secret, and ConfigMap) using the YAML files as described in Option 1, steps 1-3.

#### PostgreSQL Database Deployment

```bash
runai workspace submit postgres-deployment \
  --image postgres:13 \
  --image-pull-policy Always \
  --cpu-core-request 0.25 \
  --cpu-core-limit 1 \
  --cpu-memory-request 256Mi \
  --cpu-memory-limit 1Gi \
  --environment PGDATA="/var/lib/postgresql/data/pgdata" \
  --environment POSTGRES_DB="postgres" \
  --environment POSTGRES_USER="postgres" \
  --environment POSTGRES_PASSWORD="SECRET:postgres-secrets,POSTGRES_PASSWORD" \
  --environment APPUSER_PASSWORD="SECRET:postgres-secrets,APPUSER_PASSWORD" \
  --environment READONLYUSER_PASSWORD="SECRET:postgres-secrets,READONLYUSER_PASSWORD" \
  --port service-type=ClusterIP,container=5432,external=5432 \
  --existing-pvc claimname=postgres-data-pvc,path=/var/lib/postgresql/data \
  --configmap-map-volume name=postgres-init-script,path=/docker-entrypoint-initdb.d \
  --label app=mockdb-postgres
```


## Database Configuration

### Default Users and Passwords
- **Superuser**: `postgres` / `mysecurepassword`
- **App User**: `appuser` / `apppassword` (full access to `myapp_db`)
- **Read-Only User**: `readonlyuser` / `readonlypassword` (read-only access to `myapp_db`)

### Database Structure
The initialization script creates:
- A database named `myapp_db`
- A `users` table with sample data
- Appropriate user permissions

## pgAdmin GUI Tool (Optional)

For users who want a graphical interface to manage and test the PostgreSQL database, you can deploy pgAdmin:

```bash
runai workspace submit pgadmin \
  --image dpage/pgadmin4:latest \
  --image-pull-policy Always \
  --cpu-core-request 0.25 \
  --cpu-core-limit 1 \
  --cpu-memory-request 256Mi \
  --cpu-memory-limit 1Gi \
  --external-url container=80 \
  --environment PGADMIN_DEFAULT_EMAIL="admin@example.com" \
  --environment PGADMIN_DEFAULT_PASSWORD="admin123" \
  --environment PGADMIN_CONFIG_SERVER_MODE="True" \
  --environment PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED="False" \
  --environment SCRIPT_NAME="/mockdb/pgadmin"
```

### Accessing pgAdmin

1. **Connect to pgAdmin**: Use the workspace connection URL from RunAI and login with the credentials specified in the submit command above.

2. **Add PostgreSQL Server**: Set up the database as a new connection in pgAdmin with the following details:

   **Server Name**: You can use any descriptive name (e.g., "PostgreSQL Database")
   
   **Host/Address**: Find the service name using:
   ```bash
   kubectl -n runai-mockdb get svc -l release=postgres-deployment -o name
   ```
   
   This will typically be `iw-postgres-deployment-0-clusterip`. The full FQDN is:
   `iw-postgres-deployment-0-clusterip.runai-mockdb.svc.cluster.local`
   
   **Port**: `5432`
   
   **Username**: `postgres`
   
   **Password**: `mysecurepassword` (as defined in the secret)

## Testing and Verification

You can verify the PostgreSQL deployment is working correctly by connecting to the database and running test queries. The database includes sample data and multiple user accounts with different permission levels.

## Cleanup

To remove the PostgreSQL workload:
```bash
# If using YAML approach
kubectl delete -f runai-iw.yaml
kubectl delete -f runai-cm.yaml
kubectl delete -f runai-pvc.yaml
kubectl delete -f runai-secret.yaml

# If using CLI approach
runai workspace delete postgres-deployment
runai workspace delete pgadmin  # if deployed
```

## Files in this Directory

- `runai-iw.yaml` - InteractiveWorkload definition for PostgreSQL
- `runai-secret.yaml` - Secret containing database passwords
- `runai-pvc.yaml` - PersistentVolumeClaim for database storage
- `runai-cm.yaml` - ConfigMap with database initialization script
