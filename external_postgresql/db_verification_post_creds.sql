-- Example #1: pass variables from command line
-- psql -h postgresql.itaydb.svc.cluster.local -p 5432 -U postgres -d postgres \
--   -v db_name=backend \
--   -v backend_role=itay_b \
--   -v grafana_role=itay_g \
--   -v schema_name=grafana \
--   -f check_init_script.sql

-- Example #2: use variables in script (if not running from command line)
-- \set db_name 'backend'
-- \set backend_role 'itay_b'
-- \set grafana_role 'itay_g'
-- \set schema_name 'grafana'

\echo 'Checking initialization script execution...'
\echo 'Database: ':db_name
\echo 'Backend Role: ':backend_role
\echo 'Grafana Role: ':grafana_role
\echo 'Schema: ':schema_name
\echo ''

-- Check if database exists
\echo '1. Checking if database "':db_name'" exists:'
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name') 
        THEN '✓ Database "' || :'db_name' || '" exists'
        ELSE '✗ Database "' || :'db_name' || '" NOT found'
    END as database_check;

\echo ''

-- Check if roles exist
\echo '2. Checking if roles exist:'
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'backend_role') 
        THEN '✓ Role "' || :'backend_role' || '" exists'
        ELSE '✗ Role "' || :'backend_role' || '" NOT found'
    END as backend_role_check;

SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'grafana_role') 
        THEN '✓ Role "' || :'grafana_role' || '" exists'
        ELSE '✗ Role "' || :'grafana_role' || '" NOT found'
    END as grafana_role_check;

\echo ''

-- Check if roles can login
\echo '3. Checking if roles have login privileges:'
SELECT 
    rolname,
    CASE 
        WHEN rolcanlogin THEN '✓ Can login'
        ELSE '✗ Cannot login'
    END as login_status
FROM pg_roles 
WHERE rolname IN (:'backend_role', :'grafana_role')
ORDER BY rolname;

\echo ''

-- Check database privileges for backend role
\echo '4. Checking database privileges for ':backend_role':'
SELECT 
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM pg_database d
            JOIN pg_roles r ON d.datdba = r.oid OR 
                              has_database_privilege(r.rolname, d.datname, 'CREATE')
            WHERE d.datname = :'db_name' AND r.rolname = :'backend_role'
        ) OR EXISTS (
            SELECT 1 FROM information_schema.role_table_grants 
            WHERE grantee = :'backend_role'
        )
        THEN '✓ ' || :'backend_role' || ' has privileges on ' || :'db_name' || ' database'
        ELSE '? Database privileges check (connect to ' || :'db_name' || ' db for detailed check)'
    END as db_privileges_check;

\echo ''

-- Connect to target database to check schema and search_path
\echo '5. Connecting to database to check schema and settings...'
\c :db_name

\echo ''
\echo 'Connected to ':db_name' database'
\echo ''

-- Check if schema exists
\echo '6. Checking if "':schema_name'" schema exists:'
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = :'schema_name') 
        THEN '✓ Schema "' || :'schema_name' || '" exists'
        ELSE '✗ Schema "' || :'schema_name' || '" NOT found'
    END as schema_check;

\echo ''

-- Check schema ownership
\echo '7. Checking schema ownership:'
SELECT 
    schema_name,
    schema_owner,
    CASE 
        WHEN schema_owner = :'grafana_role' THEN '✓ Correct owner'
        ELSE '✗ Incorrect owner (should be ' || :'grafana_role' || ')'
    END as ownership_status
FROM information_schema.schemata 
WHERE schema_name = :'schema_name';

\echo ''

-- Check search_path setting for grafana user
\echo '8. Checking search_path setting for ':grafana_role':'
SELECT 
    r.rolname,
    CASE 
        WHEN drs.setconfig IS NOT NULL THEN 
            array_to_string(drs.setconfig, ', ')
        ELSE 'No user-specific settings'
    END as user_settings,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM pg_db_role_setting drs2
            JOIN pg_roles r2 ON drs2.setrole = r2.oid
            WHERE r2.rolname = :'grafana_role' 
            AND (array_to_string(drs2.setconfig, ' ') LIKE '%search_path=' || :'schema_name' || '%'
                 OR array_to_string(drs2.setconfig, ' ') LIKE '%search_path="' || :'schema_name' || '%')
        )
        THEN '✓ search_path includes ' || :'schema_name'
        WHEN EXISTS (
            SELECT 1 FROM pg_db_role_setting drs3
            JOIN pg_roles r3 ON drs3.setrole = r3.oid
            WHERE r3.rolname = :'grafana_role'
        )
        THEN '✗ search_path does not include ' || :'schema_name' || ' as first schema'
        ELSE '✗ No user-specific search_path setting found'
    END as search_path_status
FROM pg_roles r
LEFT JOIN pg_db_role_setting drs ON r.oid = drs.setrole
WHERE r.rolname = :'grafana_role';

\echo ''

-- NEW SECTION: Additional verification tests
\echo '========================================='
\echo 'ADDITIONAL VERIFICATION TESTS'
\echo '========================================='

-- Check current schema and search_path when connecting as grafana user
\echo '9. Testing connection as ':grafana_role' to verify search_path:'
-- Note: This would require password, so we'll check the setting instead
SELECT 
    r.rolname,
    r.rolconfig,
    CASE 
        WHEN r.rolconfig IS NOT NULL AND 
             array_to_string(r.rolconfig, ' ') LIKE '%search_path%' || :'schema_name' || '%'
        THEN '✓ search_path configured correctly'
        ELSE '✗ search_path may not be configured correctly'
    END as config_status
FROM pg_roles r 
WHERE r.rolname = :'grafana_role';

\echo ''

-- Check table ownership in grafana schema
\echo '10. Checking table ownership in ':schema_name' schema:'
SELECT 
    schemaname,
    tablename,
    tableowner,
    CASE 
        WHEN tableowner = :'grafana_role' THEN '✓ Correct owner'
        ELSE '✗ Incorrect owner (should be ' || :'grafana_role' || ')'
    END as ownership_status
FROM pg_tables 
WHERE schemaname = :'schema_name'
ORDER BY tablename;

-- If no tables exist yet, show that
SELECT 
    CASE 
        WHEN NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = :'schema_name')
        THEN '⚠ No tables found in ' || :'schema_name' || ' schema (this may be expected for new setup)'
        ELSE ''
    END as no_tables_message
WHERE NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = :'schema_name');

\echo ''

-- Check what objects the old user still owns (if any)
\echo '11. Checking for objects still owned by previous users:'
SELECT 
    'Tables owned by non-current users:' as check_type,
    schemaname,
    tablename,
    tableowner,
    '✗ Should be transferred to ' || :'grafana_role' as status
FROM pg_tables 
WHERE schemaname = :'schema_name' 
  AND tableowner != :'grafana_role'
  AND tableowner LIKE :'grafana_role' || '%' -- Check for similar names like itay_g_v2
ORDER BY tableowner, tablename;

-- Show message if no orphaned tables
SELECT 
    CASE 
        WHEN NOT EXISTS (
            SELECT 1 FROM pg_tables 
            WHERE schemaname = :'schema_name' 
              AND tableowner != :'grafana_role'
              AND tableowner LIKE :'grafana_role' || '%'
        )
        THEN '✓ No orphaned tables found from previous users'
        ELSE ''
    END as no_orphaned_tables
WHERE NOT EXISTS (
    SELECT 1 FROM pg_tables 
    WHERE schemaname = :'schema_name' 
      AND tableowner != :'grafana_role'
      AND tableowner LIKE :'grafana_role' || '%'
);

\echo ''

-- Check for group membership (if using role-based permissions)
\echo '12. Checking group/role membership:'
SELECT 
    r.rolname as member_role,
    g.rolname as group_role,
    '✓ Member of group: ' || g.rolname as membership_status
FROM pg_auth_members am
JOIN pg_roles r ON am.member = r.oid
JOIN pg_roles g ON am.roleid = g.oid
WHERE r.rolname IN (:'backend_role', :'grafana_role')
ORDER BY r.rolname, g.rolname;

-- Show message if no group memberships found
SELECT 
    CASE 
        WHEN NOT EXISTS (
            SELECT 1 FROM pg_auth_members am
            JOIN pg_roles r ON am.member = r.oid
            WHERE r.rolname IN (:'backend_role', :'grafana_role')
        )
        THEN '⚠ No group memberships found (direct permissions may be used instead)'
        ELSE ''
    END as no_groups_message
WHERE NOT EXISTS (
    SELECT 1 FROM pg_auth_members am
    JOIN pg_roles r ON am.member = r.oid
    WHERE r.rolname IN (:'backend_role', :'grafana_role')
);

\echo ''
\echo '========================================='
\echo 'Initialization Check Summary:'
\echo '========================================='
\echo 'Review the results above to verify that:'
\echo '- Database "':db_name'" exists'
\echo '- Roles "':backend_role'" and "':grafana_role'" exist with login privileges'
\echo '- Role "':backend_role'" has privileges on "':db_name'" database'
\echo '- Schema "':schema_name'" exists and is owned by "':grafana_role'"'
\echo '- User "':grafana_role'" has search_path set to "':schema_name'"'
\echo '- All tables in "':schema_name'" are owned by "':grafana_role'"'
\echo '- No objects are orphaned from previous user versions'
\echo '- Schema privileges are properly configured'
\echo '- Group memberships are set up (if using role-based permissions)'
\echo ''
\echo 'If any checks show ✗, the init script may not have completed successfully.'
\echo 'If any checks show ⚠, review whether this is expected for your setup.'