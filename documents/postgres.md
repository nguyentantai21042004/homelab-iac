# PostgreSQL Multi-tenant Setup Guide

> Single PostgreSQL Instance phục vụ nhiều dự án với Multi-tenant Isolation

---

## 📋 Mục lục

1. [Kịch bản Sử dụng](#kịch-bản-sử-dụng)
2. [Kiến trúc](#kiến-trúc)
3. [Bảo mật Multi-tenant](#bảo-mật-multi-tenant)
4. [Hướng dẫn Triển khai](#hướng-dẫn-triển-khai)
5. [Quản lý Database](#quản-lý-database)
6. [Kết nối từ Application](#kết-nối-từ-application)
7. [Monitoring & Troubleshooting](#monitoring--troubleshooting)
8. [Backup & Recovery](#backup--recovery)
9. [Quick Reference](#quick-reference)

---

## 🎯 Kịch bản Sử dụng

### Bước 1: Tạo PostgreSQL VM (Lần đầu tiên)

```bash
# 1. Tạo VM bằng Terraform
cd terraform
terraform apply

# Hoặc từ Admin VM (nhanh hơn)
./scripts/remote-apply.sh <admin-vm-ip> <user>

# 2. Lấy IP của PostgreSQL VM
terraform output postgres_ip
# Output: 172.16.19.10

# 3. Cập nhật inventory
cd ../ansible
# Sửa inventory/hosts.yml với IP vừa lấy

# 4. Setup VM cơ bản (hostname, network, mount disk)
ansible-playbook playbooks/setup-vm.yml -l postgres

# 5. Cài Docker + PostgreSQL
ansible-playbook playbooks/setup-postgres.yml
```

**Kết quả:** PostgreSQL đã chạy trên `172.16.19.10:5432` (không có sample databases)

---

### Bước 2: Thêm Database cho Dự án Mới

Khi bạn có dự án mới (ví dụ: `myapp`), chạy:

```bash
cd ansible

ansible-playbook playbooks/postgres-add-database.yml \
  -e "db_name=myapp" \
  -e "master_pwd=MyApp_Master_2026!" \
  -e "dev_pwd=MyApp_Dev_2026!" \
  -e "prod_pwd=MyApp_Prod_2026!" \
  -e "readonly_pwd=MyApp_Read_2026!"
```

**Kết quả:** Database `myapp` được tạo với 4 users:
- `myapp_master` - Full access (migrations, admin)
- `myapp_dev` - Create/Alter tables, CRUD (development)
- `myapp_prod` - CRUD only (production app) ⭐ **Dùng user này cho app**
- `myapp_readonly` - SELECT only (analytics, reporting)

---

### Bước 3: Kết nối từ Application

**Connection String (Production):**

```
postgresql://myapp_prod:MyApp_Prod_2026!@172.16.19.10:5432/myapp
```

**Golang Example:**

```go
import "github.com/jmoiron/sqlx"

db, err := sqlx.Connect("postgres", 
    "host=172.16.19.10 port=5432 user=myapp_prod password=MyApp_Prod_2026! dbname=myapp sslmode=disable")
if err != nil {
    log.Fatal(err)
}
defer db.Close()

// Set connection pool
db.SetMaxOpenConns(20)
db.SetMaxIdleConns(5)
db.SetConnMaxLifetime(time.Hour)
```

**Node.js Example:**

```javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: '172.16.19.10',
  port: 5432,
  user: 'myapp_prod',
  password: 'MyApp_Prod_2026!',
  database: 'myapp',
  max: 20, // Connection pool size
});

// Query
const result = await pool.query('SELECT * FROM users WHERE id = $1', [1]);
```

---

### Bước 4: Verify Security Isolation

```bash
# Test tự động
ansible-playbook playbooks/postgres-verify-isolation.yml

# Test thủ công (should FAIL - cross-database access)
PGPASSWORD=MyApp_Prod_2026! psql -h 172.16.19.10 -U myapp_prod -d kanban -c "SELECT 1;"
# Expected: ERROR: permission denied for database "kanban"

# Test thủ công (should SUCCEED - same database)
PGPASSWORD=MyApp_Prod_2026! psql -h 172.16.19.10 -U myapp_prod -d myapp -c "SELECT 1;"
# Expected: ?column? = 1
```

---

## 🏗️ Kiến trúc

### Tổng quan

```
┌─────────────────────────────────────────────────────────────────┐
│                PostgreSQL VM (172.16.19.10)                     │
│                3 vCPU | 6GB RAM                                 │
│                                                                 │
│  ┌─────────────┐         ┌──────────────────────────────┐      │
│  │ Boot Disk   │         │   Data Disk (100GB XFS)      │      │
│  │ /dev/sda    │         │   /mnt/pg_data               │      │
│  │             │         │                              │      │
│  │ - Ubuntu OS │         │   └── postgres-stack/        │      │
│  │ - Docker    │         │       ├── data/    (PGDATA)  │      │
│  └─────────────┘         │       ├── init-db/ (SQL)     │      │
│                          │       └── docker-compose.yml │      │
│                          └──────────────────────────────┘      │
│                                     │                          │
│  ┌──────────────────────────────────┴─────────────────────┐    │
│  │         Docker Container: postgres:15-alpine          │    │
│  │                                                        │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐            │    │
│  │  │  kanban  │  │  myapp   │  │ project3 │  ...       │    │
│  │  │ database │  │ database │  │ database │            │    │
│  │  └──────────┘  └──────────┘  └──────────┘            │    │
│  │                                                        │    │
│  │  Port: 5432                                            │    │
│  └────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Lợi ích Tách Boot & Data Disk

| Lợi ích | Mô tả |
|:---|:---|
| **I/O Performance** | Data đi thẳng PostgreSQL → XFS, bypass Docker OverlayFS |
| **An toàn dữ liệu** | OS hỏng? Tháo Data Disk, gắn vào VM mới → có lại toàn bộ DB |
| **Dễ mở rộng** | Expand Data Disk không ảnh hưởng OS |
| **Backup đơn giản** | Snapshot Data Disk = backup toàn bộ databases |

---

## 🔐 Bảo mật Multi-tenant

### Nguyên tắc

**1. Zero Trust Network (pg_hba.conf)**

Chỉ cho phép kết nối từ dải IP tin cậy:

```conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD
host    all             all             10.10.10.0/24           scram-sha-256
host    all             all             172.16.0.0/12           scram-sha-256
```

**2. Least Privilege (RBAC)**

Quy trình cấp quyền tự động:
1. **REVOKE PUBLIC CONNECT** - Thu hồi quyền mặc định
2. **GRANT EXPLICIT CONNECT** - Chỉ cấp cho user sở hữu
3. **SCHEMA OWNERSHIP** - Gán user làm owner của schema public

### Ma trận Phân quyền

| Hành động | master | dev | prod | readonly | User DB khác |
|:---|:---:|:---:|:---:|:---:|:---:|
| **CONNECT to DB** | ✅ | ✅ | ✅ | ✅ | ❌ |
| **CREATE TABLE** | ✅ | ✅ | ❌ | ❌ | ❌ |
| **ALTER TABLE** | ✅ | ✅ | ❌ | ❌ | ❌ |
| **DROP TABLE** | ✅ | ✅ | ❌ | ❌ | ❌ |
| **SELECT** | ✅ | ✅ | ✅ | ✅ | ❌ |
| **INSERT/UPDATE/DELETE** | ✅ | ✅ | ✅ | ❌ | ❌ |
| **DROP DATABASE** | ✅ | ❌ | ❌ | ❌ | ❌ |

### Ví dụ Isolation

```sql
-- ❌ myapp_prod KHÔNG thể connect vào kanban
psql -U myapp_prod -d kanban -c "SELECT 1;"
-- ERROR: permission denied for database "kanban"

-- ✅ myapp_prod CÓ THỂ connect vào myapp
psql -U myapp_prod -d myapp -c "SELECT 1;"
-- Success
```

---

## 🚀 Hướng dẫn Triển khai

### Prerequisites

**Trên Local Machine:**
- Terraform (`brew install terraform`)
- Ansible (`brew install ansible`)

**Trên ESXi:**
- Template VM Ubuntu với SSH key đã setup
- Network: DB-Network (172.16.19.0/24)

### Bước 1: Tạo VM

```bash
cd terraform
terraform init
terraform apply
```

**VM Specs:**
- vCPU: 3
- RAM: 6GB
- Boot Disk: 20GB
- Data Disk: 100GB (XFS)
- Network: DB-Network
- IP: 172.16.19.10 (static)

### Bước 2: Cập nhật Inventory

```bash
cd ../ansible
cp inventory/hosts.yml.example inventory/hosts.yml
```

Sửa `inventory/hosts.yml`:

```yaml
postgres_servers:
  hosts:
    postgres:
      ansible_host: 172.16.19.10
      ansible_user: tantai
```

### Bước 3: Setup VM

```bash
# Setup cơ bản (hostname, static IP, mount disk)
ansible-playbook playbooks/setup-vm.yml -l postgres

# Setup PostgreSQL
ansible-playbook playbooks/setup-postgres.yml
```

### Bước 4: Verify

```bash
# SSH vào server
ssh tantai@172.16.19.10

# Check container
docker ps

# Check databases
docker exec -it pg15_prod psql -U postgres -c "\l"

# Check users
docker exec -it pg15_prod psql -U postgres -c "\du"
```

---

## 📊 Quản lý Database

### Thêm Database Mới

```bash
ansible-playbook playbooks/postgres-add-database.yml \
  -e "db_name=project_x" \
  -e "master_pwd=SecurePass1!" \
  -e "dev_pwd=SecurePass2!" \
  -e "prod_pwd=SecurePass3!" \
  -e "readonly_pwd=SecurePass4!"
```

### Đổi Password User

```bash
ansible-playbook playbooks/postgres-change-password.yml \
  -e "username=myapp_prod" \
  -e "new_password=NewSecurePass123!"
```

### Giới hạn Connection per User

```bash
# SSH vào server
ssh tantai@172.16.19.10

# Vào psql
docker exec -it pg15_prod psql -U postgres

# Giới hạn max 20 connections
ALTER USER myapp_prod WITH CONNECTION LIMIT 20;
```

### Xem Logs

```bash
# Real-time logs
docker logs -f pg15_prod

# Last 100 lines
docker logs --tail 100 pg15_prod
```

---

## 🔌 Kết nối từ Application

### Connection String Format

```
postgresql://<user>:<password>@172.16.19.10:5432/<database>
```

### Golang (sqlx)

```go
package main

import (
    "log"
    "time"
    _ "github.com/lib/pq"
    "github.com/jmoiron/sqlx"
)

func main() {
    db, err := sqlx.Connect("postgres", 
        "host=172.16.19.10 port=5432 user=myapp_prod password=xxx dbname=myapp sslmode=disable")
    if err != nil {
        log.Fatal(err)
    }
    defer db.Close()

    // Connection pool settings
    db.SetMaxOpenConns(20)
    db.SetMaxIdleConns(5)
    db.SetConnMaxLifetime(time.Hour)

    // Test query
    var result int
    err = db.Get(&result, "SELECT 1")
    if err != nil {
        log.Fatal(err)
    }
    log.Println("Connected successfully!")
}
```

### Node.js (pg)

```javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: '172.16.19.10',
  port: 5432,
  user: 'myapp_prod',
  password: 'xxx',
  database: 'myapp',
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Query example
async function getUser(id) {
  const result = await pool.query('SELECT * FROM users WHERE id = $1', [id]);
  return result.rows[0];
}

// Test connection
pool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('Connection error:', err);
  } else {
    console.log('Connected successfully!');
  }
});
```

### Python (psycopg2)

```python
import psycopg2
from psycopg2 import pool

# Connection pool
connection_pool = psycopg2.pool.SimpleConnectionPool(
    1, 20,
    host="172.16.19.10",
    port=5432,
    user="myapp_prod",
    password="xxx",
    database="myapp"
)

# Get connection from pool
conn = connection_pool.getconn()
cursor = conn.cursor()

# Query
cursor.execute("SELECT * FROM users WHERE id = %s", (1,))
user = cursor.fetchone()

# Return connection to pool
connection_pool.putconn(conn)
```

### Environment Variables (12-factor app)

```bash
# .env file
DATABASE_URL=postgresql://myapp_prod:xxx@172.16.19.10:5432/myapp
PGHOST=172.16.19.10
PGPORT=5432
PGDATABASE=myapp
PGUSER=myapp_prod
PGPASSWORD=xxx
```

---

## 🔍 Monitoring & Troubleshooting

### Check Active Connections

```sql
SELECT datname, usename, count(*) 
FROM pg_stat_activity 
GROUP BY datname, usename 
ORDER BY count(*) DESC;
```

### Check Database Sizes

```sql
SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
WHERE datname NOT IN ('template0', 'template1', 'postgres')
ORDER BY pg_database_size(datname) DESC;
```

### Check Long-running Queries

```sql
SELECT pid, usename, datname, state, 
       now() - query_start AS duration, 
       query
FROM pg_stat_activity
WHERE state != 'idle'
  AND now() - query_start > interval '5 minutes'
ORDER BY duration DESC;
```

### Kill Stuck Connection

```sql
-- Find PID
SELECT pid, usename, datname, state, query 
FROM pg_stat_activity 
WHERE datname = 'myapp';

-- Kill connection
SELECT pg_terminate_backend(12345); -- Replace with actual PID
```

### Troubleshooting: Permission Denied

**Triệu chứng:**

```
FATAL: permission denied for database "myapp"
```

**Giải pháp:**

```sql
-- Kiểm tra quyền hiện tại
\l myapp

-- Nếu PUBLIC vẫn có quyền, revoke lại
REVOKE ALL ON DATABASE myapp FROM PUBLIC;
REVOKE CONNECT ON DATABASE myapp FROM PUBLIC;

-- Grant lại cho user cụ thể
GRANT CONNECT ON DATABASE myapp TO myapp_prod;
```

### Troubleshooting: Too Many Connections

**Nguyên nhân:** Application không dùng Connection Pool

**Giải pháp:**

```go
// Golang - Set max connections
db.SetMaxOpenConns(20)
db.SetMaxIdleConns(5)
db.SetConnMaxLifetime(time.Hour)
```

---

## 💾 Backup & Recovery

### Manual Backup

```bash
# SSH vào server
ssh tantai@172.16.19.10

# Backup single database
docker exec pg15_prod pg_dump -U postgres -Fc myapp > myapp_$(date +%Y%m%d).dump

# Backup all databases
docker exec pg15_prod pg_dumpall -U postgres > all_databases_$(date +%Y%m%d).sql
```

### Restore Database

```bash
# Restore from custom format
pg_restore -h 172.16.19.10 -U postgres -d myapp myapp_20260208.dump

# Restore from SQL
cat all_databases_20260208.sql | docker exec -i pg15_prod psql -U postgres
```

### Automated Backup Script

```bash
#!/bin/bash
# /opt/scripts/backup-postgres.sh

BACKUP_DIR="/mnt/backup/postgres"
RETENTION_DAYS=7
DATABASES="kanban smap_identity myapp"

mkdir -p $BACKUP_DIR

for DB in $DATABASES; do
  docker exec pg15_prod pg_dump -U postgres -Fc $DB > \
    $BACKUP_DIR/${DB}_$(date +%Y%m%d).dump
done

# Cleanup old backups
find $BACKUP_DIR -name "*.dump" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: $(date)"
```

**Setup Cronjob:**

```bash
# Chạy lúc 3:00 AM hàng ngày
0 3 * * * /opt/scripts/backup-postgres.sh >> /var/log/postgres-backup.log 2>&1
```

### Snapshot Data Disk (ESXi)

Cách nhanh nhất để backup toàn bộ:

1. Stop container: `docker stop pg15_prod`
2. Snapshot `/dev/sdb` từ ESXi
3. Start container: `docker start pg15_prod`

---

## 📋 Quick Reference

### Common Commands

```bash
# Add database
ansible-playbook playbooks/postgres-add-database.yml \
  -e "db_name=myapp" -e "master_pwd=xxx" -e "prod_pwd=yyy"

# Verify isolation
ansible-playbook playbooks/postgres-verify-isolation.yml

# Connect to database
psql -h 172.16.19.10 -U myapp_prod -d myapp

# Backup
docker exec pg15_prod pg_dump -U postgres -Fc myapp > backup.dump

# Restore
pg_restore -h 172.16.19.10 -U postgres -d myapp backup.dump

# View logs
docker logs -f pg15_prod

# Restart PostgreSQL
docker restart pg15_prod
```

### User Roles Cheat Sheet

| Role | Permissions | Use Case |
|:---|:---|:---|
| `{db}_master` | Full access (DDL + CRUD) | Database owner, migrations |
| `{db}_dev` | Create/Alter tables, CRUD | Development environment |
| `{db}_prod` | CRUD only (no DDL) | Production applications ⭐ |
| `{db}_readonly` | SELECT only | Analytics, reporting |

### Connection Strings

```bash
# Production (recommended)
postgresql://myapp_prod:xxx@172.16.19.10:5432/myapp

# Development
postgresql://myapp_dev:xxx@172.16.19.10:5432/myapp

# Read-only
postgresql://myapp_readonly:xxx@172.16.19.10:5432/myapp

# Master (admin only)
postgresql://myapp_master:xxx@172.16.19.10:5432/myapp
```

### Test Isolation

```bash
# Should FAIL (cross-database access)
PGPASSWORD=myapp_prod psql -h 172.16.19.10 -U myapp_prod -d kanban -c "SELECT 1;"
# Expected: ERROR: permission denied

# Should SUCCEED (same database)
PGPASSWORD=myapp_prod psql -h 172.16.19.10 -U myapp_prod -d myapp -c "SELECT 1;"
# Expected: ?column? = 1
```

---

## 📚 Tham khảo

- [PostgreSQL Official Docs](https://www.postgresql.org/docs/current/)
- [PostgreSQL RBAC Best Practices](https://www.postgresql.org/docs/current/user-manag.html)
- Ansible Playbook: `ansible/playbooks/postgres-add-database.yml`
- Init Script: `ansible/roles/postgres/files/01-rbac-setup.sql`
