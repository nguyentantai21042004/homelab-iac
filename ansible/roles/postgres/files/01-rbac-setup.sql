-- ============================================================
-- PostgreSQL RBAC Setup Script
-- NOTE: Sample databases removed. Use postgres-add-database.yml to create new databases.
-- ============================================================

-- ============================================================
-- 1. CREATE DATABASES & REVOKE PUBLIC ACCESS (Multi-tenant Isolation)
-- ============================================================

-- Sample databases removed. Use playbook to create:
-- ansible-playbook playbooks/postgres-add-database.yml -e "db_name=myapp"

-- ============================================================
-- 2. CREATE ROLES (Reusable permission groups)
-- ============================================================

-- Roles removed. They will be created per-database by postgres-add-database.yml playbook

-- ============================================================
-- 3. SAMPLE DATABASE SETUP REMOVED
-- ============================================================
-- Use postgres-add-database.yml playbook to create databases:
-- ansible-playbook playbooks/postgres-add-database.yml -e "db_name=myapp"

-- ============================================================
-- 4. SECURITY VERIFICATION & SUMMARY
-- ============================================================
-- 
-- ✅ MULTI-TENANT ISOLATION:
--   - Each database has PUBLIC access REVOKED by postgres-add-database.yml
--   - Only explicit users can CONNECT to their database
--   - Cross-database access is prevented
--
-- 🔧 TO CREATE A NEW DATABASE:
--   ansible-playbook playbooks/postgres-add-database.yml -e "db_name=myapp"
--
-- This will create:
--   - Database: myapp
--   - Users: myapp_master, myapp_dev, myapp_prod, myapp_readonly
--   - Proper RBAC permissions with multi-tenant isolation
--
-- 🧪 TEST ISOLATION (After creating databases):
--   psql -U myapp_master -d other_db -c "SELECT 1;"
--   Expected: ERROR: permission denied for database "other_db"
-- ============================================================
