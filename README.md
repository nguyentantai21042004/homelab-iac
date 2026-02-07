# Homelab IaC

> Infrastructure as Code cho ESXi homelab - Tự động hóa việc tạo và cấu hình VM

**Ngôn ngữ / Language:** [Tiếng Việt](#tiếng-việt) | [English](#english)

---

## Tiếng Việt

### Tổng quan

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              WORKFLOW                                       │
│                                                                             │
│   LOCAL MACHINE                    ESXi SERVER (192.168.1.50)               │
│   ┌─────────────┐                  ┌─────────────────────────────────┐      │
│   │             │   Mutagen Sync   │  ┌─────────┐    ┌─────────────┐ │      │
│   │  Kiro IDE   │◄────────────────►│  │ Admin   │───►│ Template VM │ │      │
│   │             │                  │  │   VM    │    └─────────────┘ │      │
│   │  - Edit     │                  │  │         │           │        │      │
│   │  - Plan     │   SSH Commands   │  │ Terraform           ▼        │      │
│   │  - Git      │─────────────────►│  │ Ansible │    ┌─────────────┐ │      │
│   │             │                  │  │ OVFTool │───►│  New VMs    │ │      │
│   └─────────────┘                  │  └─────────┘    └─────────────┘ │      │
│                                    └─────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Tại sao cần Admin VM?**

Provider `josenk/esxi` khi clone VM từ local sẽ download template về rồi upload lại → chậm. Admin VM nằm trong ESXi network, clone trực tiếp qua internal network → nhanh hơn 5-10x.

### Điểm nổi bật

| Component     | Pattern           | Mô tả                                                                  |
| ------------- | ----------------- | ---------------------------------------------------------------------- |
| **Terraform** | Dynamic Data Disk | Module tự tạo data disk nếu `data_disk_size > 0`, dùng `dynamic` block |
| **Terraform** | Reusable Module   | 1 module `esxi-vm` cho mọi VM, chỉ đổi params                          |
| **Ansible**   | Roles-based       | 10 roles tái sử dụng: 4 base + 6 service roles                        |
| **Ansible**   | 4-tier RBAC       | PostgreSQL tự tạo 4 users: master/dev/prod/readonly                    |
| **Ansible**   | Kernel Tuning     | `vm.swappiness=10`, `dirty_ratio=15` cho DB/Storage                    |
| **Ansible**   | Vault Secrets     | Password trong `group_vars/all/vault.yml`, encrypted                   |
| **Ansible**   | site.yml          | 1 lệnh setup toàn bộ infra: `ansible-playbook playbooks/site.yml`     |
| **K3s HA**    | Cluster HA        | 3 Masters + External DB + Kube-VIP (172.16.21.100)                     |
| **Storage**   | Distributed       | Longhorn Block Storage + S3 Backup                                     |
| **Scripts**   | Auto-unlock       | Tự detect và force-unlock stale Terraform locks                        |

### Quick Commands

```bash
make sync-start    # Start Mutagen sync
make apply         # Terraform apply via Admin VM
make sync-status   # Check sync status
```

### Dịch vụ Cluster (Access Info)

Add vào `/etc/hosts`: `172.16.21.100 rancher.tantai.dev longhorn.tantai.dev`

| Dịch vụ | URL | User/Pass |
|---------|-----|-----------|
| **Rancher** | `https://rancher.tantai.dev` | `admin` / (trong vault) |
| **Longhorn** | `http://longhorn.tantai.dev` | (No auth) |
| **Traefik** | `http://172.16.21.100:8080` | (Dashboard) |

### Cấu trúc Project

```
homelab-iac/
├── Makefile                      # Quick commands (make apply, make sync-start)
├── terraform/
│   ├── versions.tf               # Terraform + provider version constraints
│   ├── provider.tf               # ESXi provider config
│   ├── main.tf                   # VM definitions (admin, postgres, storage, api-gateway)
│   ├── modules/esxi-vm/          # Reusable module với dynamic data disk
│   ├── locals.tf                 # Port groups mapping
│   └── variables.tf              # ESXi credentials, template name
│
├── ansible/
│   ├── roles/                    # 10 Ansible roles (xem ansible/README.md)
│   │   ├── common/               # hostname, timezone, static IP
│   │   ├── docker/               # Docker install + daemon config
│   │   ├── data-disk/            # format + mount data disk
│   │   ├── kernel-tuning/        # sysctl params
│   │   ├── postgres/             # PostgreSQL container
│   │   ├── minio/                # MinIO + Zot Registry
│   │   ├── traefik/              # Traefik reverse proxy
│   │   ├── k3s/                  # K3s HA cluster
│   │   ├── woodpecker/           # Woodpecker CI
│   │   └── localstack/           # LocalStack Pro
│   ├── playbooks/
│   │   ├── site.yml              # Master playbook — setup toàn bộ infra
│   │   ├── setup-postgres.yml    # roles: kernel-tuning, docker, data-disk, postgres
│   │   ├── setup-storage.yml     # roles: kernel-tuning, docker, data-disk, minio
│   │   ├── setup-api-gateway.yml # roles: docker, traefik
│   │   ├── setup-k3s-cluster.yml # roles: k3s
│   │   ├── setup-cicd.yml        # roles: docker, woodpecker
│   │   ├── setup-localstack.yml  # roles: kernel-tuning, docker, data-disk, localstack
│   │   ├── setup-longhorn.yml    # Longhorn Distributed Storage
│   │   ├── setup-rancher.yml     # Rancher trên K3s
│   │   └── setup-admin-vm.yml    # Install Terraform, Ansible, OVFTool
│   ├── group_vars/
│   │   ├── all/
│   │   │   ├── common.yml        # service_ips map, shared vars
│   │   │   └── vault.yml         # Encrypted secrets
│   │   ├── postgres_servers.yml
│   │   ├── storage_servers.yml
│   │   └── ...                   # Per-group variables
│   └── inventory/
│       └── hosts.yml.example
│
├── scripts/
│   ├── lib/common.sh             # Shared functions (auto_unlock_terraform)
│   ├── sync-start.sh             # Mutagen sync with ignore patterns
│   ├── remote-apply.sh           # Auto-unlock + apply
│   └── remote-destroy.sh
│
├── tests/                        # Structural validation tests
│   └── test_role_structure.py    # pytest: role compliance checks
│
└── documents/                    # Detailed guides
```

### Yêu cầu cài đặt

#### Trên máy Local (macOS)

| Tool      | Cài đặt                                   | Mục đích                    |
| --------- | ----------------------------------------- | --------------------------- |
| Terraform | `brew install terraform`                  | Preview changes (plan)      |
| Ansible   | `brew install ansible`                    | Config VMs                  |
| Mutagen   | `brew install mutagen-io/mutagen/mutagen` | Sync code với Admin VM      |
| OVF Tool  | Download → `tools/ovftool/`               | (Optional) Export/Import VM |

#### Trên Admin VM (Ubuntu - tự động cài qua Ansible)

| Tool      | Mục đích                |
| --------- | ----------------------- |
| Terraform | Tạo/xóa VMs (nhanh)     |
| Ansible   | Config VMs              |
| OVF Tool  | Export/Import templates |

#### Trên Template VM (Ubuntu Server)

```bash
# Cài trước khi tạo template
sudo apt update
sudo apt install -y open-vm-tools openssh-server

# Tạo user
sudo adduser youruser
sudo usermod -aG sudo youruser
echo "youruser ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/youruser

# Add SSH key (quan trọng!)
mkdir -p ~/.ssh
echo "your-public-key" >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys

# Netplan cho cả 2 interface (ens36 và ens160)
sudo tee /etc/netplan/00-dhcp.yaml << 'EOF'
network:
  version: 2
  ethernets:
    ens36:
      dhcp4: true
    ens160:
      dhcp4: true
EOF
sudo netplan apply
```

### Cài đặt ban đầu

#### 1. Clone repo

```bash
git clone <repo-url>
cd homelab-iac
```

#### 2. Config Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Sửa `terraform.tfvars`:

```hcl
esxi_hostname = "192.168.1.50"
esxi_username = "root"
esxi_password = "your-password"
clone_from_vm = "template-vm"    # Tên template trên ESXi
```

#### 3. Config Ansible

```bash
cd ansible
cp inventory/hosts.yml.example inventory/hosts.yml
```

#### 4. Tạo Admin VM (lần đầu)

```bash
# Từ local (chậm nhưng chỉ 1 lần)
cd terraform
terraform init
terraform apply

# Lấy IP của Admin VM
terraform output admin_ip

# Config Admin VM
cd ../ansible
# Sửa IP trong inventory/hosts.yml
ansible-playbook playbooks/setup-vm.yml -l admin
ansible-playbook playbooks/setup-admin-vm.yml -l admin
```

#### 5. Setup Mutagen Sync

```bash
# Cài Mutagen
brew install mutagen-io/mutagen/mutagen

# Start sync
./scripts/sync-start.sh 192.168.1.100 tantai
```

### Sử dụng hàng ngày

```bash
# 1. Start sync (nếu chưa chạy)
./scripts/sync-start.sh 192.168.1.100 tantai

# 2. Edit code trên local (tự động sync)

# 3. Preview
terraform plan

# 4. Apply từ Admin VM (nhanh!)
./scripts/remote-apply.sh 192.168.1.100 tantai

# 5. Stop sync khi xong
./scripts/sync-stop.sh
```

### Network Port Groups

| Port Group   | Subnet         | Mục đích          |
| ------------ | -------------- | ----------------- |
| VM Network   | 192.168.1.0/24 | Management, Admin |
| DB-Network   | 172.16.19.0/24 | Database servers  |
| Prod-Network | 172.16.21.0/24 | Production apps   |

---

## English

### Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              WORKFLOW                                       │
│                                                                             │
│   LOCAL MACHINE                    ESXi SERVER (192.168.1.50)               │
│   ┌─────────────┐                  ┌─────────────────────────────────┐      │
│   │             │   Mutagen Sync   │  ┌─────────┐    ┌─────────────┐ │      │
│   │  Kiro IDE   │◄────────────────►│  │ Admin   │───►│ Template VM │ │      │
│   │             │                  │  │   VM    │    └─────────────┘ │      │
│   │  - Edit     │                  │  │         │           │        │      │
│   │  - Plan     │   SSH Commands   │  │ Terraform           ▼        │      │
│   │  - Git      │─────────────────►│  │ Ansible │    ┌─────────────┐ │      │
│   │             │                  │  │ OVFTool │───►│  New VMs    │ │      │
│   └─────────────┘                  │  └─────────┘    └─────────────┘ │      │
│                                    └─────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Why Admin VM?**

The `josenk/esxi` provider downloads template to local then uploads back when cloning → slow. Admin VM sits inside ESXi network, clones directly via internal network → 5-10x faster.

### Highlights

| Component     | Pattern           | Description                                                                 |
| ------------- | ----------------- | --------------------------------------------------------------------------- |
| **Terraform** | Dynamic Data Disk | Module auto-creates data disk if `data_disk_size > 0`, uses `dynamic` block |
| **Terraform** | Reusable Module   | Single `esxi-vm` module for all VMs, just change params                     |
| **Ansible**   | Roles-based       | 10 reusable roles: 4 base + 6 service roles                                |
| **Ansible**   | 4-tier RBAC       | PostgreSQL auto-creates 4 users: master/dev/prod/readonly                   |
| **Ansible**   | Kernel Tuning     | `vm.swappiness=10`, `dirty_ratio=15` for DB/Storage                         |
| **Ansible**   | Vault Secrets     | Passwords in `group_vars/all/vault.yml`, encrypted                          |
| **Ansible**   | site.yml          | Single command full infra setup: `ansible-playbook playbooks/site.yml`      |
| **K3s HA**    | Cluster HA        | 3 Masters + External DB + Kube-VIP (172.16.21.100)                          |
| **Storage**   | Distributed       | Longhorn Block Storage + S3 Backup                                          |
| **Scripts**   | Auto-unlock       | Auto-detect and force-unlock stale Terraform locks                          |

### Quick Commands

```bash
make sync-start    # Start Mutagen sync
make apply         # Terraform apply via Admin VM
make sync-status   # Check sync status
```

### Project Structure

```
homelab-iac/
├── Makefile                      # Quick commands (make apply, make sync-start)
├── terraform/
│   ├── versions.tf               # Terraform + provider version constraints
│   ├── provider.tf               # ESXi provider config
│   ├── main.tf                   # VM definitions (admin, postgres, storage, api-gateway)
│   ├── modules/esxi-vm/          # Reusable module with dynamic data disk
│   ├── locals.tf                 # Port groups mapping
│   └── variables.tf              # ESXi credentials, template name
│
├── ansible/
│   ├── roles/                    # 10 Ansible roles (see ansible/README.md)
│   │   ├── common/               # hostname, timezone, static IP
│   │   ├── docker/               # Docker install + daemon config
│   │   ├── data-disk/            # format + mount data disk
│   │   ├── kernel-tuning/        # sysctl params
│   │   ├── postgres/             # PostgreSQL container
│   │   ├── minio/                # MinIO + Zot Registry
│   │   ├── traefik/              # Traefik reverse proxy
│   │   ├── k3s/                  # K3s HA cluster
│   │   ├── woodpecker/           # Woodpecker CI
│   │   └── localstack/           # LocalStack Pro
│   ├── playbooks/
│   │   ├── site.yml              # Master playbook — full infra setup
│   │   ├── setup-postgres.yml    # roles: kernel-tuning, docker, data-disk, postgres
│   │   ├── setup-storage.yml     # roles: kernel-tuning, docker, data-disk, minio
│   │   ├── setup-api-gateway.yml # roles: docker, traefik
│   │   ├── setup-k3s-cluster.yml # roles: k3s
│   │   ├── setup-cicd.yml        # roles: docker, woodpecker
│   │   ├── setup-localstack.yml  # roles: kernel-tuning, docker, data-disk, localstack
│   │   ├── setup-longhorn.yml    # Longhorn Distributed Storage
│   │   ├── setup-rancher.yml     # Rancher on K3s
│   │   └── setup-admin-vm.yml    # Install Terraform, Ansible, OVFTool
│   ├── group_vars/
│   │   ├── all/
│   │   │   ├── common.yml        # service_ips map, shared vars
│   │   │   └── vault.yml         # Encrypted secrets
│   │   ├── postgres_servers.yml
│   │   ├── storage_servers.yml
│   │   └── ...                   # Per-group variables
│   └── inventory/
│       └── hosts.yml.example
│
├── scripts/
│   ├── lib/common.sh             # Shared functions (auto_unlock_terraform)
│   ├── sync-start.sh             # Mutagen sync with ignore patterns
│   ├── remote-apply.sh           # Auto-unlock + apply
│   └── remote-destroy.sh
│
├── tests/                        # Structural validation tests
│   └── test_role_structure.py    # pytest: role compliance checks
│
└── documents/                    # Detailed guides
```

### Requirements

#### On Local Machine (macOS)

| Tool      | Install                                   | Purpose                     |
| --------- | ----------------------------------------- | --------------------------- |
| Terraform | `brew install terraform`                  | Preview changes (plan)      |
| Ansible   | `brew install ansible`                    | Configure VMs               |
| Mutagen   | `brew install mutagen-io/mutagen/mutagen` | Sync code with Admin VM     |
| OVF Tool  | Download → `tools/ovftool/`               | (Optional) Export/Import VM |

#### On Admin VM (Ubuntu - auto-installed via Ansible)

| Tool      | Purpose                   |
| --------- | ------------------------- |
| Terraform | Create/destroy VMs (fast) |
| Ansible   | Configure VMs             |
| OVF Tool  | Export/Import templates   |

#### On Template VM (Ubuntu Server)

```bash
# Install before creating template
sudo apt update
sudo apt install -y open-vm-tools openssh-server

# Create user
sudo adduser youruser
sudo usermod -aG sudo youruser
echo "youruser ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/youruser

# Add SSH key (important!)
mkdir -p ~/.ssh
echo "your-public-key" >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys

# Netplan for both interfaces (ens36 and ens160)
sudo tee /etc/netplan/00-dhcp.yaml << 'EOF'
network:
  version: 2
  ethernets:
    ens36:
      dhcp4: true
    ens160:
      dhcp4: true
EOF
sudo netplan apply
```

### Initial Setup

#### 1. Clone repo

```bash
git clone <repo-url>
cd homelab-iac
```

#### 2. Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
esxi_hostname = "192.168.1.50"
esxi_username = "root"
esxi_password = "your-password"
clone_from_vm = "template-vm"    # Template name on ESXi
```

#### 3. Configure Ansible

```bash
cd ansible
cp inventory/hosts.yml.example inventory/hosts.yml
```

#### 4. Create Admin VM (first time only)

```bash
# From local (slow but only once)
cd terraform
terraform init
terraform apply

# Get Admin VM IP
terraform output admin_ip

# Configure Admin VM
cd ../ansible
# Update IP in inventory/hosts.yml
ansible-playbook playbooks/setup-vm.yml -l admin
ansible-playbook playbooks/setup-admin-vm.yml -l admin
```

#### 5. Setup Mutagen Sync

```bash
# Install Mutagen
brew install mutagen-io/mutagen/mutagen

# Start sync
./scripts/sync-start.sh 192.168.1.100 tantai
```

### Daily Usage

```bash
# 1. Start sync (if not running)
./scripts/sync-start.sh 192.168.1.100 tantai

# 2. Edit code locally (auto-syncs)

# 3. Preview
terraform plan

# 4. Apply from Admin VM (fast!)
./scripts/remote-apply.sh 192.168.1.100 tantai

# 5. Stop sync when done
./scripts/sync-stop.sh
```

### Network Port Groups

| Port Group   | Subnet         | Purpose           |
| ------------ | -------------- | ----------------- |
| VM Network   | 192.168.1.0/24 | Management, Admin |
| DB-Network   | 172.16.19.0/24 | Database servers  |
| Prod-Network | 172.16.21.0/24 | Production apps   |

---

## Tài liệu bổ sung / Additional Docs

- [Ansible Roles & Playbooks Guide](ansible/README.md)
- [Hướng dẫn thêm VM mới / Add New VM Guide](documents/add-vm-guide.md)
- [PostgreSQL Server Setup](documents/postgres.md)
- [MinIO + Zot Registry Setup](documents/minio-zot.md)
- [API Gateway (Traefik) Setup](documents/api-gateway.md)
- [K3s HA Cluster Setup](documents/k3s-cluster.md)
- [Longhorn Storage Guide](documents/longhorn.md)
- [Jinja2 Templates Guide](documents/jinja2-templates.md)
- [Mutagen - Cơ chế hoạt động / How it works](documents/mutagen.md)
