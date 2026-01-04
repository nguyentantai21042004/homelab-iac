# Homelab IaC

> Infrastructure as Code cho ESXi homelab - Tự động hóa việc tạo và cấu hình VM

**Ngôn ngữ / Language:** [Tiếng Việt](#tiếng-việt) | [English](#english)

---

## Tiếng Việt

### Tổng quan

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              WORKFLOW                                        │
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

### Cấu trúc Project

```
homelab-iac/
├── terraform/                    # Infrastructure
│   ├── main.tf                   # Định nghĩa VMs
│   ├── provider.tf               # Kết nối ESXi
│   ├── variables.tf              # Input variables
│   ├── locals.tf                 # Port groups
│   ├── outputs.tf                # VM IPs output
│   ├── terraform.tfvars          # Credentials (gitignored)
│   └── modules/esxi-vm/          # Reusable VM module
│
├── ansible/                      # Configuration
│   ├── ansible.cfg               # Ansible settings
│   ├── inventory/hosts.yml       # Server list
│   └── playbooks/
│       ├── setup-vm.yml          # Basic VM config
│       └── setup-admin-vm.yml    # Admin VM tools
│
├── scripts/                      # Automation
│   ├── sync-start.sh             # Start Mutagen sync
│   ├── sync-stop.sh              # Stop sync
│   ├── remote-apply.sh           # Terraform apply on Admin VM
│   └── remote-destroy.sh         # Terraform destroy on Admin VM
│
├── linux/ovftool/                # OVF Tool cho Admin VM (Linux)
└── tools/ovftool/                # OVF Tool cho local (macOS)
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
| Prod-Network | 172.16.20.0/24 | Production apps   |

---

## English

### Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              WORKFLOW                                        │
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

### Project Structure

```
homelab-iac/
├── terraform/                    # Infrastructure
│   ├── main.tf                   # VM definitions
│   ├── provider.tf               # ESXi connection
│   ├── variables.tf              # Input variables
│   ├── locals.tf                 # Port groups
│   ├── outputs.tf                # VM IPs output
│   ├── terraform.tfvars          # Credentials (gitignored)
│   └── modules/esxi-vm/          # Reusable VM module
│
├── ansible/                      # Configuration
│   ├── ansible.cfg               # Ansible settings
│   ├── inventory/hosts.yml       # Server list
│   └── playbooks/
│       ├── setup-vm.yml          # Basic VM config
│       └── setup-admin-vm.yml    # Admin VM tools
│
├── scripts/                      # Automation
│   ├── sync-start.sh             # Start Mutagen sync
│   ├── sync-stop.sh              # Stop sync
│   ├── remote-apply.sh           # Terraform apply on Admin VM
│   └── remote-destroy.sh         # Terraform destroy on Admin VM
│
├── linux/ovftool/                # OVF Tool for Admin VM (Linux)
└── tools/ovftool/                # OVF Tool for local (macOS)
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
| Prod-Network | 172.16.20.0/24 | Production apps   |

---

## Tài liệu bổ sung / Additional Docs

- [Hướng dẫn thêm VM mới / Add New VM Guide](documents/add-vm-guide.md)
- [PostgreSQL Server Setup](documents/postgres.md)
- [Mutagen - Cơ chế hoạt động / How it works](documents/mutagen.md)
