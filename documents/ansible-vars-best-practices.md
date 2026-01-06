# Ansible Variables Best Practices

> Hướng dẫn quản lý biến trong Ansible playbooks cho homelab-iac

**Ngôn ngữ / Language:** [Tiếng Việt](#tiếng-việt) | [English](#english)

---

## Tiếng Việt

### Cấu trúc Variables

#### 1. Inventory Variables (`inventory/hosts.yml`)

**Mục đích**: Thông tin host-specific (IP, hostname, disk devices...)

```yaml
postgres_servers:
  hosts:
    postgres:
      ansible_host: 172.16.19.10
      ansible_user: tantai
      vm_hostname: "postgres"
      static_ip: "172.16.19.10/24"
      gateway: "172.16.19.1"
      data_disk_device: "/dev/sdb"
      data_mount_point: "/mnt/pg_data"
```

**Khi nào dùng**: IP, user, hostname, disk paths - những thứ thay đổi theo từng host.

#### 2. Group Variables (`group_vars/<group>.yml`)

**Mục đích**: Cấu hình logic theo nhóm server

Ví dụ: `group_vars/postgres_servers.yml`
```yaml
postgres_version: "15"
postgres_password: "{{ vault_postgres_password }}"
pg_data_path: "/mnt/pg_data"
pg_stack_path: "/mnt/pg_data/postgres-stack"
```

Ví dụ: `group_vars/api_gateway_servers.yml`
```yaml
traefik_stack_path: "/opt/traefik"
traefik_acme_email: "nguyentantai.dev@gmail.com"
traefik_dashboard_user: "tantai"
traefik_dashboard_password: "{{ vault_traefik_dashboard_password }}"
storage_backend_ip: "172.16.21.10"
```

**Khi nào dùng**: Paths, ports, usernames, config - giống nhau cho tất cả hosts trong group.

#### 3. Vault Variables (`group_vars/all/vault.yml`)

**Mục đích**: Passwords và sensitive data

```yaml
# Vault file for sensitive data
# Encrypt this file with: ansible-vault encrypt group_vars/all/vault.yml

vault_postgres_password: "21042004!"
vault_minio_password: "21042004!"
vault_zot_password: "21042004!"
vault_traefik_dashboard_password: "21042004!"
```

**Khi nào dùng**: Passwords, API keys, certificates - mọi thứ nhạy cảm.

**Bảo mật**: Nên encrypt với `ansible-vault encrypt group_vars/all/vault.yml`

### Pattern Playbook Chuẩn

#### Template Playbook

```yaml
---
# Playbook: Description

- name: Playbook Name
  hosts: <group_name>
  become: yes

  vars_files:
    - ../group_vars/<group_name>.yml
    - ../group_vars/all/vault.yml

  tasks:
    # ... tasks here ...
```

#### Các Playbook Hiện Tại

| Playbook | Hosts | Vars Files | Mục Đích |
|----------|-------|------------|----------|
| `setup-vm.yml` | `all` | (không cần) | Setup cơ bản: hostname, IP, disk |
| `setup-admin-vm.yml` | `admin` | (không cần) | Install Terraform, Ansible, OVF Tool |
| `setup-postgres.yml` | `postgres_servers` | ✅ | Deploy PostgreSQL với Docker |
| `postgres-add-database.yml` | `postgres_servers` | ✅ | Tạo database mới với RBAC |
| `postgres-change-password.yml` | `postgres_servers` | ✅ | Đổi password user |
| `setup-storage.yml` | `storage_servers` | ✅ | Deploy MinIO + Zot Registry |
| `setup-api-gateway.yml` | `api_gateway_servers` | ✅ | Deploy Traefik API Gateway |

### Lợi Ích Pattern Này

1. **Dễ maintain**: Tất cả config tập trung ở `group_vars/`, không rải rác trong playbooks
2. **Bảo mật**: Passwords tách riêng trong `vault.yml`, có thể encrypt
3. **Tái sử dụng**: Playbook không hardcode, chạy được cho nhiều environment
4. **Đồng nhất**: Mọi playbook đều load vars theo cùng 1 cách

### Thêm Service Mới

Ví dụ: Thêm service `kafka`

#### Bước 1: Tạo Group Vars

`group_vars/kafka_servers.yml`:
```yaml
kafka_version: "3.5"
kafka_data_path: "/mnt/kafka_data"
kafka_stack_path: "/mnt/kafka_data/kafka-stack"
kafka_admin_user: "admin"
kafka_admin_password: "{{ vault_kafka_password }}"
```

#### Bước 2: Thêm Password vào Vault

`group_vars/all/vault.yml`:
```yaml
vault_kafka_password: "your-secure-password"
```

#### Bước 3: Tạo Playbook

`playbooks/setup-kafka.yml`:
```yaml
---
- name: Setup Kafka
  hosts: kafka_servers
  become: yes

  vars_files:
    - ../group_vars/kafka_servers.yml
    - ../group_vars/all/vault.yml

  tasks:
    # ... tasks using kafka_data_path, kafka_admin_user, etc
```

### Troubleshooting

#### Lỗi: "variable is undefined"

**Nguyên nhân**: Playbook không load được vars từ group_vars

**Giải pháp**:
1. Kiểm tra `vars_files` trong playbook có trỏ đúng path
2. Kiểm tra `hosts:` trong playbook match với group name trong inventory
3. Chạy từ thư mục `ansible/`: `cd ansible && ansible-playbook playbooks/xxx.yml`

**Debug**:
```bash
# Kiểm tra biến được load đúng không
ansible <host/group> -m debug -a "var=<variable_name>"

# Ví dụ
ansible postgres -m debug -a "var=pg_data_path"
ansible storage -m debug -a "var=storage_data_path"
ansible api-gateway -m debug -a "var=traefik_stack_path"
```

#### Lỗi: Recursive loop in template

**Nguyên nhân**: Trong task's `vars:`, đặt lại tên biến giống với biến đã có trong scope

**Giải pháp**: Đổi tên biến trong task `vars:` hoặc bỏ task vars đi dùng trực tiếp biến từ group_vars

**Ví dụ lỗi**:
```yaml
- name: Copy config
  template:
    src: config.yml.j2
    dest: /etc/config.yml
  vars:
    storage_backend_ip: "{{ storage_backend_ip | default('...') }}"  # ❌ Recursive!
```

**Sửa**:
```yaml
- name: Copy config
  template:
    src: config.yml.j2
    dest: /etc/config.yml
  # Không cần vars:, dùng trực tiếp biến từ group_vars
```

---

## English

### Variables Structure

#### 1. Inventory Variables (`inventory/hosts.yml`)

**Purpose**: Host-specific information (IP, hostname, disk devices...)

**When to use**: IP addresses, usernames, hostnames, disk paths - things that vary per host.

#### 2. Group Variables (`group_vars/<group>.yml`)

**Purpose**: Logical configuration per server group

**When to use**: Paths, ports, usernames, config - same for all hosts in group.

#### 3. Vault Variables (`group_vars/all/vault.yml`)

**Purpose**: Passwords and sensitive data

**When to use**: Passwords, API keys, certificates - anything sensitive.

**Security**: Should encrypt with `ansible-vault encrypt group_vars/all/vault.yml`

### Standard Playbook Pattern

#### Playbook Template

```yaml
---
# Playbook: Description

- name: Playbook Name
  hosts: <group_name>
  become: yes

  vars_files:
    - ../group_vars/<group_name>.yml
    - ../group_vars/all/vault.yml

  tasks:
    # ... tasks here ...
```

### Benefits of This Pattern

1. **Easy maintenance**: All config centralized in `group_vars/`, not scattered in playbooks
2. **Secure**: Passwords separated in `vault.yml`, can be encrypted
3. **Reusable**: Playbooks have no hardcoded values, work for multiple environments
4. **Consistent**: All playbooks load vars the same way

### Adding New Services

Example: Adding `kafka` service

#### Step 1: Create Group Vars

`group_vars/kafka_servers.yml`:
```yaml
kafka_version: "3.5"
kafka_data_path: "/mnt/kafka_data"
kafka_stack_path: "/mnt/kafka_data/kafka-stack"
kafka_admin_user: "admin"
kafka_admin_password: "{{ vault_kafka_password }}"
```

#### Step 2: Add Password to Vault

`group_vars/all/vault.yml`:
```yaml
vault_kafka_password: "your-secure-password"
```

#### Step 3: Create Playbook

`playbooks/setup-kafka.yml`:
```yaml
---
- name: Setup Kafka
  hosts: kafka_servers
  become: yes

  vars_files:
    - ../group_vars/kafka_servers.yml
    - ../group_vars/all/vault.yml

  tasks:
    # ... tasks using kafka_data_path, kafka_admin_user, etc
```

### Troubleshooting

#### Error: "variable is undefined"

**Cause**: Playbook cannot load vars from group_vars

**Solution**:
1. Check `vars_files` in playbook points to correct path
2. Check `hosts:` in playbook matches group name in inventory
3. Run from `ansible/` directory: `cd ansible && ansible-playbook playbooks/xxx.yml`

**Debug**:
```bash
# Check if variable is loaded correctly
ansible <host/group> -m debug -a "var=<variable_name>"

# Examples
ansible postgres -m debug -a "var=pg_data_path"
ansible storage -m debug -a "var=storage_data_path"
ansible api-gateway -m debug -a "var=traefik_stack_path"
```

#### Error: Recursive loop in template

**Cause**: In task's `vars:`, redefining variable with same name as existing variable in scope

**Solution**: Rename variable in task `vars:` or remove task vars and use group_vars directly

