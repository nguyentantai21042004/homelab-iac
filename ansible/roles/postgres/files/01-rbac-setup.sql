-- ============================================================
-- PostgreSQL RBAC Setup Script
-- Databases: kanban, smap_identity
-- Users per DB: master, dev, prod, readonly (with DB prefix)
-- ============================================================

-- ============================================================
-- 1. CREATE DATABASES & REVOKE PUBLIC ACCESS (Multi-tenant Isolation)
-- ============================================================

-- KANBAN Database
CREATE DATABASE kanban;
-- 🔒 CRITICAL: Revoke default PUBLIC access (prevent cross-tenant access)
REVOKE ALL ON DATABASE kanban FROM PUBLIC;
REVOKE CONNECT ON DATABASE kanban FROM PUBLIC;

-- SMAP_IDENTITY Database
CREATE DATABASE smap_identity;
-- 🔒 CRITICAL: Revoke default PUBLIC access (prevent cross-tenant access)
REVOKE ALL ON DATABASE smap_identity FROM PUBLIC;
REVOKE CONNECT ON DATABASE smap_identity FROM PUBLIC;

-- ============================================================
-- 2. CREATE ROLES (Reusable permission groups)
-- ============================================================

-- Role: Full access (owner level)
CREATE ROLE role_master;

-- Role: Developer (can create/alter tables, cannot drop database)
CREATE ROLE role_dev;

-- Role: Production app (CRUD only, no DDL)
CREATE ROLE role_prod;

-- Role: Read only
CREATE ROLE role_readonly;

-- ============================================================
-- 3. KANBAN DATABASE - Users & Permissions
-- ============================================================

-- Create users for kanban database
CREATE USER kanban_master WITH PASSWORD 'kanban_master';
CREATE USER kanban_dev WITH PASSWORD 'kanban_dev';
CREATE USER kanban_prod WITH PASSWORD 'kanban_prod';
CREATE USER kanban_readonly WITH PASSWORD 'kanban_readonly';

-- Connect to kanban database for permission setup
\c kanban

-- 🔒 Grant EXPLICIT connect only to kanban users (Zero Trust principle)
GRANT CONNECT ON DATABASE kanban TO kanban_master, kanban_dev, kanban_prod, kanban_readonly;

-- MASTER: Full ownership
ALTER DATABASE kanban OWNER TO kanban_master;
GRANT ALL PRIVILEGES ON DATABASE kanban TO kanban_master;
GRANT ALL PRIVILEGES ON SCHEMA public TO kanban_master;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO kanban_master;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO kanban_master;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO kanban_master;

-- DEV: Can create/alter tables, sequences, functions. Cannot drop database
GRANT USAGE, CREATE ON SCHEMA public TO kanban_dev;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO kanban_dev;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO kanban_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO kanban_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO kanban_dev;
-- Allow CREATE TABLE, ALTER TABLE
GRANT CREATE ON SCHEMA public TO kanban_dev;

-- PROD: CRUD only (SELECT, INSERT, UPDATE, DELETE). No DDL (CREATE/ALTER/DROP)
GRANT USAGE ON SCHEMA public TO kanban_prod;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO kanban_prod;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO kanban_prod;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO kanban_prod;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO kanban_prod;

-- READONLY: SELECT only
GRANT USAGE ON SCHEMA public TO kanban_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO kanban_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO kanban_readonly;

-- ============================================================
-- 4. SMAP_IDENTITY DATABASE - Users & Permissions
-- ============================================================

-- Switch back to default database to create users
\c postgres

-- Create users for smap_identity database
CREATE USER smap_identity_master WITH PASSWORD 'smap_identity_master';
CREATE USER smap_identity_dev WITH PASSWORD 'smap_identity_dev';
CREATE USER smap_identity_prod WITH PASSWORD 'smap_identity_prod';
CREATE USER smap_identity_readonly WITH PASSWORD 'smap_identity_readonly';

-- Connect to smap_identity database for permission setup
\c smap_identity

-- 🔒 Grant EXPLICIT connect only to smap_identity users (Zero Trust principle)
GRANT CONNECT ON DATABASE smap_identity TO smap_identity_master, smap_identity_dev, smap_identity_prod, smap_identity_readonly;

-- MASTER: Full ownership
ALTER DATABASE smap_identity OWNER TO smap_identity_master;
GRANT ALL PRIVILEGES ON DATABASE smap_identity TO smap_identity_master;
GRANT ALL PRIVILEGES ON SCHEMA public TO smap_identity_master;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO smap_identity_master;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO smap_identity_master;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO smap_identity_master;

-- DEV: Can create/alter tables, sequences, functions. Cannot drop database
GRANT USAGE, CREATE ON SCHEMA public TO smap_identity_dev;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO smap_identity_dev;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO smap_identity_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO smap_identity_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO smap_identity_dev;
GRANT CREATE ON SCHEMA public TO smap_identity_dev;

-- PROD: CRUD only (SELECT, INSERT, UPDATE, DELETE). No DDL
GRANT USAGE ON SCHEMA public TO smap_identity_prod;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO smap_identity_prod;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO smap_identity_prod;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO smap_identity_prod;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO smap_identity_prod;

-- READONLY: SELECT only
GRANT USAGE ON SCHEMA public TO smap_identity_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO smap_identity_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO smap_identity_readonly;

-- ============================================================
-- 5. SECURITY VERIFICATION & SUMMARY
-- ============================================================
-- 
-- ✅ MULTI-TENANT ISOLATION ACHIEVED:
--   - Each database has PUBLIC access REVOKED
--   - Only explicit users can CONNECT to their database
--   - kanban_master CANNOT connect to smap_identity
--   - smap_identity_prod CANNOT connect to kanban
--
-- KANBAN DATABASE:
--   kanban_master   - Full access (owner)
--   kanban_dev      - Create/Alter tables, CRUD
--   kanban_prod     - CRUD only
--   kanban_readonly - SELECT only
--
-- SMAP_IDENTITY DATABASE:
--   smap_identity_master   - Full access (owner)
--   smap_identity_dev      - Create/Alter tables, CRUD
--   smap_identity_prod     - CRUD only
--   smap_identity_readonly - SELECT only
--
-- 🧪 TEST ISOLATION (Run these commands to verify):
--   psql -U kanban_master -d smap_identity -c "SELECT 1;"
--   Expected: ERROR: permission denied for database "smap_identity"
--
--   psql -U smap_identity_prod -d kanban -c "SELECT 1;"
--   Expected: ERROR: permission denied for database "kanban"
-- ============================================================
