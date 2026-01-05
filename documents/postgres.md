# PostgreSQL Server Setup

> PostgreSQL 15 trên Docker với RBAC, tối ưu Storage

**Ngôn ngữ / Language:** [Tiếng Việt](#tiếng-việt) | [English](#english)

---

## Tiếng Việt

### Mục lục

- [Kiến trúc](#kiến-trúc)
- [Tại sao tách Boot OS và Data Disk?](#tại-sao-tách-boot-os-và-data-disk)
- [RBAC - Phân quyền User](#rbac---phân-quyền-user)
- [Triển khai](#triển-khai)
- [Quản lý sau triển khai](#quản-lý-sau-triển-khai)
- [Kết nối từ ứng dụng](#kết-nối-từ-ứng-dụng)
- [Backup & Recovery](#backup--recovery)

---

### Kiến trúc

```
┌─────────────────────────────────────────────────────────────────┐
│                    POSTGRES VM (172.16.19.10)                   │
│                    3 vCPU | 6GB RAM                             │
│                                                                 │
│  ┌─────────────────┐         ┌─────────────────────────────┐    │
│  │   Boot Disk     │         │      Data Disk (100GB)      │    │
│  │   /dev/sda      │         │      /dev/sdb               │    │
│  │                 │         │                             │    │
│  │  - Ubuntu OS    │         │  Mount: /mnt/pg_data        │    │
│  │  - Docker       │         │  Format: XFS                │    │
│  │  - System files │         │                             │    │
│  │                 │         │  └── postgres-stack/        │    │
│  │                 │         │      ├── data/     (PGDATA) │    │
│  │                 │         │      ├── init-db/  (SQL)    │    │
│  │                 │         │      └── docker-compose.yml │    │
│  └─────────────────┘         └─────────────────────────────┘    │
│                                        │                        │
│  ┌─────────────────────────────────────┴───────────────────┐    │
│  │                 Docker Container                        │    │
│  │                 postgres:15-alpine                      │    │
│  │                                                         │    │
│  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │    │
│  │   │   kanban    │  │smap_identity│  │  (future)   │     │    │
│  │   │  database   │  │  database   │  │  databases  │     │    │
│  │   └─────────────┘  └─────────────┘  └─────────────┘     │    │
│  │                                                         │    │
│  │   Port: 5432                                            │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

---

### Tại sao tách Boot OS và Data Disk?

| Lợi ích             | Mô tả                                                                 |
| ------------------- | --------------------------------------------------------------------- |
| **I/O Performance** | Data đi thẳng từ PostgreSQL → XFS filesystem, bypass Docker OverlayFS |
| **An toàn dữ liệu** | OS hỏng? Tháo Data Disk, gắn vào VM mới → có lại toàn bộ DB           |
| **Dễ mở rộng**      | Cần thêm dung lượng? Expand Data Disk, không ảnh hưởng OS             |
| **Backup đơn giản** | Snapshot Data Disk = backup toàn bộ databases                         |

**Kernel tuning cho DB:**

```
vm.swappiness = 10           # Giảm swap, ưu tiên RAM
vm.dirty_ratio = 15          # Tối ưu write buffer
vm.dirty_background_ratio = 5
```

---

### RBAC - Phân quyền User

Mỗi database có 4 loại user với prefix là tên database:

```
┌─────────────────────────────────────────────────────────────────┐
│                         PERMISSION MATRIX                       │
├─────────────┬─────────┬─────────┬─────────┬─────────────────────┤
│   User      │ SELECT  │ INSERT  │ CREATE  │ DROP DB             │
│   Type      │ UPDATE  │ DELETE  │ ALTER   │                     │
│             │         │         │ TABLE   │                     │
├─────────────┼─────────┼─────────┼─────────┼─────────────────────┤
│   master    │   ✓     │   ✓     │   ✓     │   ✓ (owner)         │
│   dev       │   ✓     │   ✓     │   ✓     │   ✗                 │
│   prod      │   ✓     │   ✓     │   ✗     │   ✗                 │
│   readonly  │   ✓     │   ✗     │   ✗     │   ✗                 │
└─────────────┴─────────┴─────────┴─────────┴─────────────────────┘
```

**Users hiện tại:**

| Database      | User                     | Mục đích sử dụng              |
| ------------- | ------------------------ | ----------------------------- |
| kanban        | `kanban_master`          | Admin, migration, maintenance |
| kanban        | `kanban_dev`             | Development, tạo bảng mới     |
| kanban        | `kanban_prod`            | Production app (CRUD)         |
| kanban        | `kanban_readonly`        | Reporting, analytics          |
| smap_identity | `smap_identity_master`   | Admin, migration              |
| smap_identity | `smap_identity_dev`      | Development                   |
| smap_identity | `smap_identity_prod`     | Production app                |
| smap_identity | `smap_identity_readonly` | Reporting                     |

---

### Triển khai

#### Bước 1: Tạo VM với Terraform

```bash
# Từ Admin VM (nhanh)
./scripts/remote-apply.sh 192.168.1.100 tantai

# Hoặc từ local
cd terraform && terraform apply
```

VM specs: 3 vCPU, 6GB RAM, 100GB data disk

#### Bước 2: Lấy IP và update inventory

```bash
terraform output postgres_ip
```

Sửa `ansible/inventory/hosts.yml`:

```yaml
postgres:
  ansible_host: <IP từ output>
```

#### Bước 3: Đổi password (QUAN TRỌNG!)

Sửa file `ansible/files/postgres/01-rbac-setup.sql`:

```sql
CREATE USER kanban_master WITH PASSWORD 'YOUR_SECURE_PASSWORD';
CREATE USER kanban_dev WITH PASSWORD 'YOUR_SECURE_PASSWORD';
-- ... tương tự cho các user khác
```

⚠️ Script này chỉ chạy **1 lần** khi PostgreSQL init lần đầu!

#### Bước 4: Chạy Ansible

```bash
cd ansible

# Setup cơ bản (hostname, static IP, mount disk)
ansible-playbook playbooks/setup-vm.yml -l postgres

# Setup Docker + PostgreSQL
ansible-playbook playbooks/setup-postgres.yml
```

#### Bước 5: Verify

```bash
# SSH vào postgres server
ssh tantai@172.16.19.10

# Check container
docker ps

# Check databases
docker exec -it pg15_prod psql -U postgres -c "\l"

# Check users
docker exec -it pg15_prod psql -U postgres -c "\du"
```

---

### Quản lý sau triển khai

#### Thêm database mới

```bash
ansible-playbook playbooks/postgres-add-database.yml -e "db_name=myapp"
```

Với custom password:

```bash
ansible-playbook playbooks/postgres-add-database.yml \
  -e "db_name=myapp" \
  -e "master_pwd=xxx" \
  -e "dev_pwd=xxx" \
  -e "prod_pwd=xxx" \
  -e "readonly_pwd=xxx"
```

#### Đổi password user

```bash
ansible-playbook playbooks/postgres-change-password.yml \
  -e "username=kanban_dev" \
  -e "new_password=new_secure_password"
```

#### Thao tác trực tiếp với PostgreSQL

```bash
# SSH vào server
ssh tantai@172.16.19.10

# Vào psql
docker exec -it pg15_prod psql -U postgres

# Các lệnh hữu ích
\l                    # List databases
\du                   # List users
\c kanban             # Connect to database
\dt                   # List tables
\q                    # Quit
```

#### Xem logs

```bash
docker logs -f pg15_prod
```

---

### Kết nối từ ứng dụng

#### Connection String

```
postgresql://<user>:<password>@172.16.19.10:5432/<database>
```

**Ví dụ:**

```
# Production app
postgresql://kanban_prod:xxx@172.16.19.10:5432/kanban

# Development
postgresql://kanban_dev:xxx@172.16.19.10:5432/kanban

# Read-only reporting
postgresql://kanban_readonly:xxx@172.16.19.10:5432/kanban
```

#### Environment variables

```bash
# .env file
DATABASE_URL=postgresql://kanban_prod:xxx@172.16.19.10:5432/kanban
PGHOST=172.16.19.10
PGPORT=5432
PGDATABASE=kanban
PGUSER=kanban_prod
PGPASSWORD=xxx
```

---

### Backup & Recovery

#### Manual backup

```bash
ssh tantai@172.16.19.10

# Backup single database
docker exec pg15_prod pg_dump -U postgres kanban > kanban_backup.sql

# Backup all databases
docker exec pg15_prod pg_dumpall -U postgres > all_databases_backup.sql
```

#### Restore

```bash
# Restore single database
cat kanban_backup.sql | docker exec -i pg15_prod psql -U postgres -d kanban

# Restore all
cat all_databases_backup.sql | docker exec -i pg15_prod psql -U postgres
```

#### Snapshot Data Disk (ESXi)

Cách nhanh nhất để backup toàn bộ:

1. Stop container: `docker stop pg15_prod`
2. Snapshot `/dev/sdb` từ ESXi
3. Start container: `docker start pg15_prod`

---

## English

### Table of Contents

- [Architecture](#architecture)
- [Why Separate Boot OS and Data Disk?](#why-separate-boot-os-and-data-disk)
- [RBAC - User Permissions](#rbac---user-permissions)
- [Deployment](#deployment)
- [Post-deployment Management](#post-deployment-management)
- [Application Connection](#application-connection)
- [Backup & Recovery](#backup--recovery-1)

---

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    POSTGRES VM (172.16.19.10)                   │
│                    3 vCPU | 6GB RAM                             │
│                                                                 │
│  ┌─────────────────┐         ┌─────────────────────────────┐    │
│  │   Boot Disk     │         │      Data Disk (100GB)      │    │
│  │   /dev/sda      │         │      /dev/sdb               │    │
│  │                 │         │                             │    │
│  │  - Ubuntu OS    │         │  Mount: /mnt/pg_data        │    │
│  │  - Docker       │         │  Format: XFS                │    │
│  │  - System files │         │                             │    │
│  │                 │         │  └── postgres-stack/        │    │
│  │                 │         │      ├── data/     (PGDATA) │    │
│  │                 │         │      ├── init-db/  (SQL)    │    │
│  │                 │         │      └── docker-compose.yml │    │
│  └─────────────────┘         └─────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

---

### Why Separate Boot OS and Data Disk?

| Benefit             | Description                                                                    |
| ------------------- | ------------------------------------------------------------------------------ |
| **I/O Performance** | Data goes directly from PostgreSQL → XFS filesystem, bypasses Docker OverlayFS |
| **Data Safety**     | OS corrupted? Detach Data Disk, attach to new VM → all DBs recovered           |
| **Easy Scaling**    | Need more space? Expand Data Disk without affecting OS                         |
| **Simple Backup**   | Snapshot Data Disk = backup all databases                                      |

---

### RBAC - User Permissions

Each database has 4 user types with database name prefix:

| User Type | SELECT/UPDATE | INSERT/DELETE | CREATE/ALTER | DROP DB   |
| --------- | ------------- | ------------- | ------------ | --------- |
| master    | ✓             | ✓             | ✓            | ✓ (owner) |
| dev       | ✓             | ✓             | ✓            | ✗         |
| prod      | ✓             | ✓             | ✗            | ✗         |
| readonly  | ✓             | ✗             | ✗            | ✗         |

---

### Deployment

#### Step 1: Create VM with Terraform

```bash
./scripts/remote-apply.sh 192.168.1.100 tantai
```

#### Step 2: Update passwords (IMPORTANT!)

Edit `ansible/files/postgres/01-rbac-setup.sql` before running Ansible.

#### Step 3: Run Ansible

```bash
cd ansible
ansible-playbook playbooks/setup-vm.yml -l postgres
ansible-playbook playbooks/setup-postgres.yml
```

---

### Post-deployment Management

#### Add new database

```bash
ansible-playbook playbooks/postgres-add-database.yml -e "db_name=myapp"
```

#### Change user password

```bash
ansible-playbook playbooks/postgres-change-password.yml \
  -e "username=kanban_dev" \
  -e "new_password=xxx"
```

---

### Application Connection

```
postgresql://<user>:<password>@172.16.19.10:5432/<database>
```

---

### Backup & Recovery

```bash
# Backup
docker exec pg15_prod pg_dump -U postgres kanban > backup.sql

# Restore
cat backup.sql | docker exec -i pg15_prod psql -U postgres -d kanban
```
