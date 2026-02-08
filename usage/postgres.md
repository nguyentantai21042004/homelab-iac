# PostgreSQL - Hướng dẫn Sử dụng

## 🎯 Kịch bản Sử dụng

### 1️⃣ Tạo PostgreSQL VM (Lần đầu tiên)

**⚠️ QUAN TRỌNG:** Phải chạy từ **Admin VM**, không chạy từ Mac local (thiếu ovftool)

**Cách 1: Dùng Makefile (Khuyến nghị - Nhanh nhất)**

```bash
# Trên Mac local
make sync-start         # Sync code lên Admin VM (lần đầu)
make apply-postgres     # Tự động SSH vào Admin VM và chạy terraform apply -target=module.postgres
```

**Cách 2: Thủ công**

```bash
# Bước 1: Sync code lên Admin VM
# Trên Mac local:
./scripts/sync-start.sh 192.168.1.100 tantai

# Bước 2: SSH vào Admin VM
ssh tantai@192.168.1.100

# Bước 3: Init terraform (lần đầu tiên)
cd ~/homelab-iac/terraform
terraform init

# Bước 4: Tạo CHỈ PostgreSQL VM
terraform apply -target=module.postgres

# Giải thích:
# - Không có -target: Tạo TẤT CẢ VMs (postgres, storage, k3s, cicd, etc.)
# - Có -target=module.postgres: CHỈ tạo PostgreSQL VM
```

```bash
# Bước 5: Lấy IP của PostgreSQL VM (trên Admin VM)
terraform output postgres_ip
# Output: 172.16.19.10
```

```bash
# Bước 6: Cập nhật inventory (trên Mac local)
cd ansible
# Sửa file inventory/hosts.yml:

postgres_servers:
  hosts:
    postgres:
      ansible_host: 172.16.19.10  # ← IP từ bước 5
      ansible_user: tantai
```

```bash
# Bước 7: Setup VM cơ bản (hostname, network, mount disk)
# Chạy từ Mac local
cd ansible
ansible-playbook playbooks/setup-vm.yml -l postgres

# -l postgres: CHỈ chạy trên postgres server, không chạy trên các servers khác
```

```bash
# Bước 8: Cài Docker + PostgreSQL
ansible-playbook playbooks/setup-postgres.yml

# Playbook này tự động:
# - Cài Docker
# - Mount data disk (/dev/sdb → /mnt/pg_data)
# - Tạo PostgreSQL container
# - Tạo 2 databases mẫu: kanban, smap_identity
```

**✅ Xong!** PostgreSQL đã chạy trên `172.16.19.10:5432`

**Verify:**

```bash
# SSH vào PostgreSQL server
ssh tantai@172.16.19.10

# Check container
docker ps
# CONTAINER ID   IMAGE                  STATUS
# abc123         postgres:15-alpine     Up 2 minutes

# Check databases
docker exec -it pg15_prod psql -U postgres -c "\l"
# List of databases:
#   kanban
#   smap_identity
```

---

### 2️⃣ Tạo Database cho Dự án Mới

Mỗi khi có dự án mới, chạy lệnh này:

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

| User             | Password           | Quyền               | Dùng cho              |
| :--------------- | :----------------- | :------------------ | :-------------------- |
| `myapp_master`   | MyApp_Master_2026! | Full access         | Admin, migrations     |
| `myapp_dev`      | MyApp_Dev_2026!    | Create tables, CRUD | Development           |
| `myapp_prod`     | MyApp_Prod_2026!   | CRUD only           | **Production app** ⭐ |
| `myapp_readonly` | MyApp_Read_2026!   | SELECT only         | Analytics             |

---

### 3️⃣ Kết nối từ Application

**Connection String (dùng cho production app):**

```
postgresql://myapp_prod:MyApp_Prod_2026!@172.16.19.10:5432/myapp
```

**Golang:**

```go
import "github.com/jmoiron/sqlx"

db, err := sqlx.Connect("postgres",
    "host=172.16.19.10 port=5432 user=myapp_prod password=MyApp_Prod_2026! dbname=myapp sslmode=disable")

// Connection pool
db.SetMaxOpenConns(20)
db.SetMaxIdleConns(5)
```

**Node.js:**

```javascript
const { Pool } = require("pg");

const pool = new Pool({
  host: "172.16.19.10",
  port: 5432,
  user: "myapp_prod",
  password: "MyApp_Prod_2026!",
  database: "myapp",
  max: 20,
});
```

---

### 4️⃣ Verify Security Isolation

```bash
# Test tự động
ansible-playbook playbooks/postgres-verify-isolation.yml

# Test thủ công - Should FAIL (user myapp không vào được DB khác)
PGPASSWORD=MyApp_Prod_2026! psql -h 172.16.19.10 -U myapp_prod -d kanban -c "SELECT 1;"
# Expected: ERROR: permission denied for database "kanban"

# Test thủ công - Should SUCCEED (user myapp vào được DB của mình)
PGPASSWORD=MyApp_Prod_2026! psql -h 172.16.19.10 -U myapp_prod -d myapp -c "SELECT 1;"
# Expected: ?column? = 1
```

---

## 📊 Ma trận Quyền hạn Chi tiết

### Tổng quan

| User         | Database Owner | DDL (CREATE/ALTER/DROP) | CRUD | SELECT Only | Cross-DB Access |
| :----------- | :------------: | :---------------------: | :--: | :---------: | :-------------: |
| **master**   |       ✅       |           ✅            |  ✅  |     ✅      |       ❌        |
| **dev**      |       ❌       |           ✅            |  ✅  |     ✅      |       ❌        |
| **prod**     |       ❌       |           ❌            |  ✅  |     ✅      |       ❌        |
| **readonly** |       ❌       |           ❌            |  ❌  |     ✅      |       ❌        |

### Chi tiết từng User

#### 1. Master User

**Quyền hạn:**

- ✅ Database owner
- ✅ CREATE/ALTER/DROP tables, sequences, functions
- ✅ Full CRUD (SELECT, INSERT, UPDATE, DELETE)
- ✅ Can DROP DATABASE

**SQL Grants:**

```sql
ALTER DATABASE myapp OWNER TO myapp_master;
GRANT ALL PRIVILEGES ON DATABASE myapp TO myapp_master;
GRANT ALL PRIVILEGES ON SCHEMA public TO myapp_master;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO myapp_master;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO myapp_master;
```

**Use case:** Admin, migrations, schema changes

---

#### 2. Dev User

**Quyền hạn:**

- ✅ CREATE/ALTER/DROP tables, sequences, functions
- ✅ Full CRUD (SELECT, INSERT, UPDATE, DELETE)
- ❌ Cannot DROP DATABASE

**SQL Grants:**

```sql
GRANT USAGE, CREATE ON SCHEMA public TO myapp_dev;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO myapp_dev;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO myapp_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO myapp_dev;
GRANT CREATE ON SCHEMA public TO myapp_dev;
```

**Use case:** Development, testing, schema prototyping

---

#### 3. Prod User ⭐

**Quyền hạn:**

- ✅ Full CRUD (SELECT, INSERT, UPDATE, DELETE)
- ✅ Can use sequences (for auto-increment)
- ❌ Cannot CREATE/ALTER/DROP tables
- ❌ Cannot TRUNCATE TABLE

**SQL Grants:**

```sql
GRANT USAGE ON SCHEMA public TO myapp_prod;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO myapp_prod;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO myapp_prod;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO myapp_prod;
```

**Use case:** Production applications (recommended)

---

#### 4. Readonly User

**Quyền hạn:**

- ✅ SELECT from all tables
- ❌ Cannot INSERT, UPDATE, DELETE
- ❌ Cannot CREATE/ALTER/DROP any objects

**SQL Grants:**

```sql
GRANT USAGE ON SCHEMA public TO myapp_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO myapp_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO myapp_readonly;
```

**Use case:** Analytics, reporting, monitoring

---

## 🧪 Test Cases

### Test Prod User (CRUD Only)

```sql
-- Connect as prod
\c myapp myapp_prod

-- ✅ Should succeed: Select
SELECT * FROM users;

-- ✅ Should succeed: Insert
INSERT INTO users (name) VALUES ('Bob');

-- ✅ Should succeed: Update
UPDATE users SET name = 'Bobby' WHERE name = 'Bob';

-- ✅ Should succeed: Delete
DELETE FROM users WHERE name = 'Bobby';

-- ❌ Should fail: Create table
CREATE TABLE test (id INT);
-- ERROR: permission denied for schema public

-- ❌ Should fail: Alter table
ALTER TABLE users ADD COLUMN age INT;
-- ERROR: must be owner of table users

-- ❌ Should fail: Drop table
DROP TABLE users;
-- ERROR: must be owner of table users
```

### Test Cross-Database Isolation

```sql
-- ❌ Should fail: myapp_prod cannot access kanban
\c kanban myapp_prod
-- FATAL: permission denied for database "kanban"

-- ✅ Should succeed: myapp_prod can access myapp
\c myapp myapp_prod
-- Success
```

---

## 📋 Quick Commands

```bash
# Thêm database mới
ansible-playbook playbooks/postgres-add-database.yml \
  -e "db_name=myapp" -e "master_pwd=xxx" -e "prod_pwd=yyy"

# Verify isolation
ansible-playbook playbooks/postgres-verify-isolation.yml

# Connect to database
psql -h 172.16.19.10 -U myapp_prod -d myapp

# Backup database
docker exec pg15_prod pg_dump -U postgres -Fc myapp > backup.dump

# Restore database
pg_restore -h 172.16.19.10 -U postgres -d myapp backup.dump

# View logs
docker logs -f pg15_prod

# Restart PostgreSQL
docker restart pg15_prod
```

---

## 🔗 Xem thêm

Chi tiết đầy đủ: [documents/postgres.md](../documents/postgres.md)
