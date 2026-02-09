# PostgreSQL Schema Isolation

## Tổng quan

Quản lý PostgreSQL với **schema isolation** - mỗi service có schema riêng, user riêng, và **không thể thấy data của service khác**.

### Kiến trúc

```
Database: smap
├── schema_auth      → auth_master, auth_prod, auth_readonly
├── schema_order     → order_master, order_prod, order_readonly
└── schema_payment   → payment_master, payment_prod, payment_readonly
```

### Đặc điểm

✅ **Full Isolation**: User A không thể thấy schema B  
✅ **search_path**: Mỗi user tự động vào schema của mình  
✅ **No PUBLIC access**: Schema public bị revoke  
✅ **Tiết kiệm tài nguyên**: 1 database thay vì nhiều databases

---

## So sánh Approaches

### Multi-Database (Cách cũ)
```
PostgreSQL
├── Database: auth_db    → auth users
├── Database: order_db   → order users
└── Database: payment_db → payment users
```

**Ưu điểm:** Isolation mạnh nhất  
**Nhược điểm:** Tốn tài nguyên, khó quản lý, không thể JOIN cross-database

### Multi-Schema (Recommended)
```
PostgreSQL
└── Database: smap
    ├── schema_auth    → auth users
    ├── schema_order   → order users
    └── schema_payment → payment users
```

**Ưu điểm:** Tiết kiệm tài nguyên, dễ quản lý, RBAC chặt chẽ  
**Nhược điểm:** Isolation yếu hơn một chút (nhưng vẫn đủ mạnh)

**Recommendation:** Dùng Multi-Schema cho microservices  

---

## Quick Start

### 1. Initialize database

```bash
make pg-init-db DB=smap
```

### 2. Add service schemas

```bash
make pg-add-schema SERVICE=auth DB=smap
make pg-add-schema SERVICE=order DB=smap
make pg-add-schema SERVICE=payment DB=smap
```

### 3. Verify isolation

```bash
make pg-verify DB=smap
```

### 4. Connect từ application

```python
# Service Auth
DATABASE_URL = "postgresql://auth_prod:auth_prod_pwd@postgres-host:5432/smap"

# Service Order
DATABASE_URL = "postgresql://order_prod:order_prod_pwd@postgres-host:5432/smap"
```

---

## Playbooks

### 1. Tạo service schema mới

```bash
ansible-playbook playbooks/postgres-add-service-schema.yml \
  -e "service_name=auth db_name=smap"
```

**Tạo:**
- Schema: `schema_auth`
- Users: `auth_master`, `auth_prod`, `auth_readonly`
- Isolation: User auth không thấy schema khác

**Passwords mặc định:**
- `auth_master_pwd`
- `auth_prod_pwd`
- `auth_readonly_pwd`

**Override password:**
```bash
ansible-playbook playbooks/postgres-add-service-schema.yml \
  -e "service_name=auth master_pwd=secure123 prod_pwd=prod456"
```

---

### 2. Liệt kê tất cả schemas

```bash
ansible-playbook playbooks/postgres-list-schemas.yml -e "db_name=smap"
```

**Hiển thị:**
- Tất cả schemas và số lượng tables
- Users và schemas họ có quyền truy cập
- search_path của mỗi user

---

### 3. Verify isolation

```bash
ansible-playbook playbooks/postgres-verify-isolation.yml -e "db_name=smap"
```

**Kiểm tra:**
- ✅ Mỗi user chỉ thấy schema của mình
- ✅ Cross-schema access bị block
- ✅ Public schema bị revoke
- ❌ Phát hiện isolation breach (nếu có)

---

### 4. Xóa service schema

```bash
# Cần confirm để tránh xóa nhầm
ansible-playbook playbooks/postgres-delete-service-schema.yml \
  -e "service_name=auth db_name=smap confirm_delete=yes"
```

**⚠️ WARNING:** Xóa toàn bộ data trong schema!

**Xóa:**
- Schema `schema_auth` và tất cả tables
- Users: `auth_master`, `auth_prod`, `auth_readonly`
- Terminate active connections

---

### 5. Đổi password

```bash
ansible-playbook playbooks/postgres-update-service-password.yml \
  -e "service_name=auth user_type=prod new_password=newpass123"
```

**user_type:** `master`, `prod`, hoặc `readonly`

---

### 6. Fix isolation (cho database cũ)

```bash
ansible-playbook playbooks/postgres-fix-isolation.yml -e "db_name=smap"
```

**Sửa:**
- Revoke PUBLIC access
- Set search_path cho tất cả service users
- Đảm bảo isolation hoàn toàn

---

## Workflow thực tế

### Setup database mới

```bash
# 1. Tạo database smap (nếu chưa có)
ansible-playbook playbooks/postgres-setup.yml

# 2. Tạo service schemas
ansible-playbook playbooks/postgres-add-service-schema.yml -e "service_name=auth"
ansible-playbook playbooks/postgres-add-service-schema.yml -e "service_name=order"
ansible-playbook playbooks/postgres-add-service-schema.yml -e "service_name=payment"

# 3. Verify isolation
ansible-playbook playbooks/postgres-verify-isolation.yml
```

### Kết nối từ application

```python
# Service Auth
DATABASE_URL = "postgresql://auth_prod:auth_prod_pwd@postgres-host:5432/smap"

# Service Order  
DATABASE_URL = "postgresql://order_prod:order_prod_pwd@postgres-host:5432/smap"
```

**Khi connect:**
- Auth service chỉ thấy `schema_auth`
- Order service chỉ thấy `schema_order`
- Không cần prefix `schema_auth.table_name`, chỉ cần `table_name`

### Test isolation

```bash
# Connect as auth_prod
psql -U auth_prod -d smap -h postgres-host

# Thử xem schemas
\dn
# Expected: Chỉ thấy schema_auth

# Thử xem tables của order
SELECT * FROM schema_order.orders;
# Expected: ERROR: permission denied for schema schema_order

# Thử tạo table
CREATE TABLE users (id INT);
# Expected: Table được tạo trong schema_auth tự động
```

---

## So sánh với cách cũ

| Feature | Cách cũ (1 DB - Nhiều User) | Cách mới (1 DB - Nhiều Schema) |
|---------|----------------------------|--------------------------------|
| Isolation | ❌ Không có | ✅ Full isolation |
| Cross-service access | ❌ User A thấy tables của B | ✅ Blocked hoàn toàn |
| Schema prefix | ❌ Cần `public.table` | ✅ Tự động vào schema riêng |
| Security | ⚠️ Dựa vào naming convention | ✅ RBAC chặt chẽ |
| Scalability | ⚠️ Khó quản lý khi nhiều service | ✅ Dễ thêm service mới |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────┐
│         PostgreSQL Container                │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │      Database: smap                 │   │
│  │                                     │   │
│  │  ┌──────────────────────────────┐  │   │
│  │  │  schema_auth                 │  │   │
│  │  │  - users, sessions tables    │  │   │
│  │  │                              │  │   │
│  │  │  Users:                      │  │   │
│  │  │  ✓ auth_master (DDL+CRUD)    │  │   │
│  │  │  ✓ auth_prod (CRUD)          │  │   │
│  │  │  ✓ auth_readonly (SELECT)    │  │   │
│  │  └──────────────────────────────┘  │   │
│  │                                     │   │
│  │  ┌──────────────────────────────┐  │   │
│  │  │  schema_order                │  │   │
│  │  │  - orders, items tables      │  │   │
│  │  │                              │  │   │
│  │  │  Users:                      │  │   │
│  │  │  ✓ order_master, prod, ro    │  │   │
│  │  └──────────────────────────────┘  │   │
│  │                                     │   │
│  │  🔒 Isolation:                      │   │
│  │  - auth_prod CANNOT see schema_order│   │
│  │  - Each user: search_path = own schema│
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

---

## Troubleshooting

### User không connect được

```bash
# Check user tồn tại
docker exec -i pg15_prod psql -U postgres -c "\du"

# Check database permissions
docker exec -i pg15_prod psql -U postgres -c "\l"
```

### User thấy được schema khác

```bash
# Run fix isolation
ansible-playbook playbooks/postgres-fix-isolation.yml

# Verify lại
ansible-playbook playbooks/postgres-verify-isolation.yml
```

### Quên password

```bash
# Reset password
ansible-playbook playbooks/postgres-update-service-password.yml \
  -e "service_name=auth user_type=prod new_password=newpass"
```

---

## Best Practices

1. **Dùng prod user cho application**: Không dùng master user trong production
2. **Rotate passwords định kỳ**: Dùng playbook update-password
3. **Verify isolation sau mỗi thay đổi**: Chạy verify-isolation.yml
4. **Backup trước khi xóa**: Schema deletion không thể undo
5. **Dùng vault cho passwords**: Không hardcode trong playbook

---

## Migration từ hệ thống cũ

```bash
# 1. Backup data hiện tại
pg_dump -U postgres smap > backup.sql

# 2. Tạo schemas mới
ansible-playbook playbooks/postgres-add-service-schema.yml -e "service_name=auth"

# 3. Migrate data
# Copy tables từ public sang schema_auth
psql -U postgres -d smap -c "
  CREATE TABLE schema_auth.users AS SELECT * FROM public.users;
  DROP TABLE public.users;
"

# 4. Fix isolation
ansible-playbook playbooks/postgres-fix-isolation.yml

# 5. Verify
ansible-playbook playbooks/postgres-verify-isolation.yml
```
