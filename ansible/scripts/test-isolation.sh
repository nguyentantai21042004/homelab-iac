#!/bin/bash
# Quick test script for PostgreSQL schema isolation
# Usage: ./scripts/test-isolation.sh <service_name> <db_name>

set -e

SERVICE_NAME=${1:-auth}
DB_NAME=${2:-smap}
POSTGRES_HOST=${3:-172.16.19.10}

echo "============================================================"
echo "Testing Schema Isolation"
echo "============================================================"
echo "Service: $SERVICE_NAME"
echo "Database: $DB_NAME"
echo "Host: $POSTGRES_HOST"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Test 1: Check if user exists"
echo "----------------------------"
docker exec -i pg15_prod psql -U postgres -c "\du ${SERVICE_NAME}_prod" 2>&1 | grep -q "${SERVICE_NAME}_prod" && \
  echo -e "${GREEN}✅ PASS${NC}: User ${SERVICE_NAME}_prod exists" || \
  echo -e "${RED}❌ FAIL${NC}: User ${SERVICE_NAME}_prod not found"
echo ""

echo "Test 2: Check if schema exists"
echo "-------------------------------"
docker exec -i pg15_prod psql -U postgres -d $DB_NAME -c "\dn schema_${SERVICE_NAME}" 2>&1 | grep -q "schema_${SERVICE_NAME}" && \
  echo -e "${GREEN}✅ PASS${NC}: Schema schema_${SERVICE_NAME} exists" || \
  echo -e "${RED}❌ FAIL${NC}: Schema schema_${SERVICE_NAME} not found"
echo ""

echo "Test 3: Check search_path"
echo "-------------------------"
SEARCH_PATH=$(docker exec -i pg15_prod psql -U postgres -d $DB_NAME -t -c "SELECT setting FROM pg_db_role_setting WHERE setrole = (SELECT oid FROM pg_roles WHERE rolname = '${SERVICE_NAME}_prod') AND setconfig[1] LIKE 'search_path=%';" | xargs)
if [[ "$SEARCH_PATH" == *"schema_${SERVICE_NAME}"* ]]; then
  echo -e "${GREEN}✅ PASS${NC}: search_path is set to schema_${SERVICE_NAME}"
else
  echo -e "${RED}❌ FAIL${NC}: search_path not set correctly (got: $SEARCH_PATH)"
fi
echo ""

echo "Test 4: User can connect to database"
echo "------------------------------------"
docker exec -i pg15_prod psql -U ${SERVICE_NAME}_prod -d $DB_NAME -c "SELECT 1;" > /dev/null 2>&1 && \
  echo -e "${GREEN}✅ PASS${NC}: User can connect to database" || \
  echo -e "${RED}❌ FAIL${NC}: User cannot connect to database"
echo ""

echo "Test 5: User can see only their schema"
echo "---------------------------------------"
VISIBLE_SCHEMAS=$(docker exec -i pg15_prod psql -U ${SERVICE_NAME}_prod -d $DB_NAME -t -c "\dn" | grep -v "pg_" | grep -v "information_schema" | wc -l | xargs)
if [ "$VISIBLE_SCHEMAS" -eq 1 ]; then
  echo -e "${GREEN}✅ PASS${NC}: User sees only 1 schema (their own)"
else
  echo -e "${YELLOW}⚠️  WARNING${NC}: User sees $VISIBLE_SCHEMAS schemas (expected 1)"
  docker exec -i pg15_prod psql -U ${SERVICE_NAME}_prod -d $DB_NAME -c "\dn"
fi
echo ""

echo "Test 6: User cannot access public schema"
echo "-----------------------------------------"
docker exec -i pg15_prod psql -U ${SERVICE_NAME}_prod -d $DB_NAME -c "SELECT has_schema_privilege('${SERVICE_NAME}_prod', 'public', 'USAGE');" 2>&1 | grep -q "f" && \
  echo -e "${GREEN}✅ PASS${NC}: User cannot access public schema" || \
  echo -e "${RED}❌ FAIL${NC}: User can access public schema (isolation breach!)"
echo ""

echo "============================================================"
echo "Test Summary"
echo "============================================================"
echo ""
echo "If all tests passed, your schema isolation is working correctly!"
echo ""
echo "To test cross-schema access (should fail):"
echo "  docker exec -i pg15_prod psql -U ${SERVICE_NAME}_prod -d $DB_NAME -c 'SELECT * FROM schema_other.table;'"
echo ""
echo "Expected: ERROR: permission denied for schema schema_other"
echo ""
