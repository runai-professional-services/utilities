# PostgreSQL Database Verification Scripts for RunAI

This directory contains PostgreSQL verification scripts designed to check if a PostgreSQL database is properly configured and ready for RunAI deployment.

## Overview

These scripts perform comprehensive checks to verify that a PostgreSQL database has been properly initialized with the correct:
- Database structure
- User roles and permissions
- Schema configuration
- Search path settings
- Table ownership

## Scripts

### 1. `db_verification.sql`
**Basic verification script** that performs essential checks to ensure the database is ready for RunAI.

**Checks performed:**
- Database existence
- Role existence (backend and grafana roles)
- Login privileges for roles
- Database privileges for backend role
- Schema existence and ownership
- Search path configuration for grafana user

### 2. `db_verification_post_creds.sql`
**Extended verification script** that includes all basic checks plus additional verification tests for post-credential setup scenarios.

**Additional checks beyond the basic script:**
- Table ownership verification in grafana schema
- Detection of orphaned objects from previous user versions
- Group/role membership verification
- Enhanced search_path configuration validation
- Comprehensive privilege verification

## Usage

### Prerequisites
- PostgreSQL client (`psql`) installed
- Access to the PostgreSQL server with appropriate privileges
- Database connection parameters (host, port, username, password)

### Running the Scripts

#### Method 1: Command Line Variables
```bash
psql -h <hostname> -p <port> -U <username> -d postgres \
  -v db_name=<database_name> \
  -v backend_role=<backend_role_name> \
  -v grafana_role=<grafana_role_name> \
  -v schema_name=<schema_name> \
  -f db_verification.sql
```

#### Method 2: Interactive Mode
1. Connect to PostgreSQL:
   ```bash
   psql -h <hostname> -p <port> -U <username> -d postgres
   ```

2. Set variables in psql:
   ```sql
   \set db_name 'your_database_name'
   \set backend_role 'your_backend_role'
   \set grafana_role 'your_grafana_role'
   \set schema_name 'your_schema_name'
   ```

3. Run the script:
   ```sql
   \i db_verification.sql
   ```

### Example Usage
```bash
# Basic verification
psql -h postgresql.example.com -p 5432 -U postgres -d postgres \
  -v db_name=runai_backend \
  -v backend_role=runai_backend_user \
  -v grafana_role=runai_grafana_user \
  -v schema_name=grafana \
  -f db_verification.sql

# Extended verification (post-credentials)
psql -h postgresql.example.com -p 5432 -U postgres -d postgres \
  -v db_name=runai_backend \
  -v backend_role=runai_backend_user \
  -v grafana_role=runai_grafana_user \
  -v schema_name=grafana \
  -f db_verification_post_creds.sql
```

## Expected Results

### Successful Verification
When the database is properly configured, you should see:
- ✓ Database exists
- ✓ Roles exist with login privileges
- ✓ Backend role has database privileges
- ✓ Schema exists and is owned by grafana role
- ✓ Grafana user has search_path configured correctly
- ✓ All tables are properly owned (extended script)

### Common Issues
- ✗ Database not found - Database initialization failed
- ✗ Role not found - User creation failed
- ✗ Cannot login - Role privileges not set correctly
- ✗ Schema not found - Schema creation failed
- ✗ Incorrect owner - Ownership transfer failed
- ✗ Search path not configured - User settings not applied
