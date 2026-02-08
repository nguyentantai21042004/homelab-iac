# Ansible — Homelab Infrastructure

## Tổ chức

```
ansible/
├── roles/           # 10 roles tái sử dụng
├── playbooks/       # Playbooks khai báo hosts + roles
├── group_vars/      # Biến theo inventory group (auto-loaded)
│   └── all/         # Biến dùng chung cho mọi host
├── inventory/       # Danh sách servers
└── ansible.cfg      # Ansible config
```

## Cách hoạt động

Mỗi playbook chỉ khai báo **hosts** và **roles** — không có inline tasks. Ansible tự động load biến từ `group_vars/` theo inventory group.

```yaml
# Ví dụ: playbooks/setup-postgres.yml
- name: Setup PostgreSQL Server
  hosts: postgres_servers
  become: true
  roles:
    - role: kernel-tuning
      vars:
        sysctl_params:
          - { name: "vm.swappiness", value: "10" }
    - role: docker
    - role: data-disk
      vars:
        data_mount_point: "{{ pg_data_path }}"
        disk_fstype: xfs
    - role: postgres
```

## Roles

### Base Roles (dùng chung)

| Role            | Chức năng                               | Defaults                                 |
| --------------- | --------------------------------------- | ---------------------------------------- |
| `common`        | hostname, timezone, static IP (netplan) | `common_timezone: "Asia/Ho_Chi_Minh"`    |
| `docker`        | Cài Docker, daemon.json, log rotation   | `overlay2`, `json-file`, `max-size: 10m` |
| `data-disk`     | Format + mount data disk (idempotent)   | `/dev/sdb`, `/mnt/data`, `ext4`          |
| `kernel-tuning` | Apply sysctl params (skip nếu rỗng)     | `sysctl_params: []`                      |

### Service Roles

| Role         | Chức năng                             | Templates                                                        |
| ------------ | ------------------------------------- | ---------------------------------------------------------------- |
| `postgres`   | PostgreSQL container + RBAC init      | `docker-compose.yml.j2`                                          |
| `minio`      | MinIO + Zot Registry                  | `.env.j2`, `docker-compose.yml.j2`, `zot-config.json.j2`         |
| `traefik`    | Traefik reverse proxy + Let's Encrypt | `traefik.yml.j2`, `dynamic_conf.yml.j2`, `docker-compose.yml.j2` |
| `k3s`        | K3s HA cluster + Kube-VIP             | `kube-vip.yaml.j2`, `traefik-config.yaml.j2`                     |
| `woodpecker` | Woodpecker CI (server + agent)        | `docker-compose.yml.j2`                                          |
| `localstack` | LocalStack Pro                        | `docker-compose.yml.j2`                                          |

## Dependency Graph

```
setup-postgres:     kernel-tuning → docker → data-disk → postgres
setup-storage:      kernel-tuning → docker → data-disk → minio
setup-api-gateway:  docker → traefik
setup-k3s-cluster:  k3s
setup-cicd:         docker → woodpecker
setup-localstack:   kernel-tuning → docker → data-disk → localstack
```

## Biến (Variables)

### Thứ tự ưu tiên (thấp → cao)

1. `roles/*/defaults/main.yml` — Role defaults
2. `group_vars/all/common.yml` — Shared vars (`service_ips`, `data_disk_device`)
3. `group_vars/all/vault.yml` — Encrypted secrets
4. `group_vars/<group>.yml` — Group-specific vars
5. Inventory `host_vars` — Host-specific vars
6. Playbook role `vars:` — Inline overrides (cao nhất)

### service_ips (single source of truth)

Tất cả IP được quản lý tập trung trong `group_vars/all/common.yml`:

```yaml
service_ips:
  postgres: "172.16.19.10"
  storage: "172.16.21.10"
  api_gateway: "192.168.1.101"
  localstack: "172.16.21.20"
  cicd: "172.16.21.21"
  k3s_vip: "172.16.21.100"
```

Các file group_vars khác reference qua `{{ service_ips.postgres }}` thay vì hardcode IP.

## Sử dụng

### Setup toàn bộ infra (từ đầu)

```bash
ansible-playbook playbooks/site.yml --ask-vault-pass
```

### Setup từng service

```bash
ansible-playbook playbooks/setup-postgres.yml
ansible-playbook playbooks/setup-storage.yml
ansible-playbook playbooks/setup-api-gateway.yml
ansible-playbook playbooks/setup-k3s-cluster.yml
ansible-playbook playbooks/setup-cicd.yml
ansible-playbook playbooks/setup-localstack.yml
```

### Utility playbooks

```bash
# Add new database with multi-tenant isolation
ansible-playbook playbooks/postgres-add-database.yml \
  -e "db_name=myapp" \
  -e "master_pwd=xxx" \
  -e "prod_pwd=yyy"

# Verify multi-tenant isolation (security test)
ansible-playbook playbooks/postgres-verify-isolation.yml

# Change PostgreSQL passwords
ansible-playbook playbooks/postgres-change-password.yml

# Export K3s kubeconfig
ansible-playbook playbooks/export-kubeconfig.yml
```

**📖 PostgreSQL Multi-tenant Guide:** See [documents/postgres-multi-tenant.md](../documents/postgres-multi-tenant.md) for detailed architecture and security model.

## Vault (Secrets)

```bash
# Tạo vault file
ansible-vault create group_vars/all/vault.yml

# Sửa vault
ansible-vault edit group_vars/all/vault.yml

# Chạy playbook với vault
ansible-playbook playbooks/site.yml --ask-vault-pass
```

## Thêm role mới

1. Tạo thư mục `roles/<tên>/` với ít nhất `tasks/main.yml` và `defaults/main.yml`
2. Nếu cần templates → đặt trong `roles/<tên>/templates/`
3. Nếu cần handlers → đặt trong `roles/<tên>/handlers/main.yml`
4. Thêm role vào playbook tương ứng
5. Chạy `pytest tests/test_role_structure.py` để verify cấu trúc
