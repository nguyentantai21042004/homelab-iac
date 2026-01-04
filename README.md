# Homelab IaC

Infrastructure as Code cho homelab ESXi server.

**Ngôn ngữ / Language:** [Tiếng Việt](#tiếng-việt) | [English](#english)

---

## Tiếng Việt

### Mục lục

- [Giới thiệu](#giới-thiệu)
- [Yêu cầu](#yêu-cầu)
- [Cấu trúc project](#cấu-trúc-project)
- [Cài đặt](#cài-đặt)
- [Chuẩn bị Template VM](#chuẩn-bị-template-vm)
- [Sử dụng](#sử-dụng)
  - [Terraform - Tạo VM](#terraform---tạo-vm)
  - [Ansible - Config VM](#ansible---config-vm)
- [Thêm VM mới](#thêm-vm-mới)

### Giới thiệu

Repo này dùng để quản lý infrastructure của homelab ESXi server bằng code:

- **Terraform**: Tạo/xóa VM trên ESXi
- **Ansible**: Config bên trong VM (hostname, IP, cài đặt services)

### Yêu cầu

#### Trên máy local (macOS/Linux)

| Tool      | Version | Cài đặt                                                                                               |
| --------- | ------- | ----------------------------------------------------------------------------------------------------- |
| Terraform | >= 1.0  | `brew install terraform`                                                                              |
| Ansible   | >= 2.9  | `brew install ansible`                                                                                |
| OVF Tool  | >= 4.0  | [Download từ VMware](https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest) |

#### Trên ESXi server

- ESXi 6.7+ với SSH enabled
- Datastore có template VM sẵn
- Network port groups đã tạo

#### Trên Template VM

- Ubuntu Server 22.04+ (hoặc distro khác)
- `open-vm-tools` đã cài (để Terraform lấy được IP)
- User có quyền sudo
- SSH enabled

### Cấu trúc project

```
.
├── terraform/
│   ├── main.tf              # Định nghĩa các VMs
│   ├── provider.tf          # Kết nối ESXi
│   ├── variables.tf         # Biến input
│   ├── outputs.tf           # Output (IP của VMs)
│   ├── locals.tf            # Giá trị cố định (port groups)
│   ├── terraform.tfvars     # Giá trị thật (gitignored)
│   └── modules/
│       └── esxi-vm/         # Module tái sử dụng
│
├── ansible/
│   ├── ansible.cfg          # Config Ansible
│   ├── inventory/
│   │   └── hosts.yml        # Danh sách servers
│   └── playbooks/
│       └── setup-vm.yml     # Playbook setup VM
│
└── tools/
    └── ovftool/             # VMware OVF Tool (gitignored)
```

### Cài đặt

#### 1. Clone repo

```bash
git clone <repo-url>
cd homelab-iac
```

#### 2. Cài OVF Tool

Download từ VMware và giải nén vào `tools/ovftool/`, sau đó:

```bash
# Cho phép chạy (macOS)
xattr -cr tools/ovftool/

# Tạo symlink
sudo ln -sf "$(pwd)/tools/ovftool/ovftool" /usr/local/bin/ovftool
```

#### 3. Config Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Sửa `terraform.tfvars`:

```hcl
esxi_hostname = "192.168.1.50"      # IP ESXi server
esxi_username = "root"
esxi_password = "your-password"
clone_from_vm = "template-vm"       # Tên template VM trên ESXi
```

#### 4. Config Ansible

```bash
cd ansible
cp inventory/hosts.yml.example inventory/hosts.yml
```

Sửa `inventory/hosts.yml` với thông tin VM.

### Chuẩn bị Template VM

Template VM cần có sẵn trên ESXi. Các bước tạo:

1. Tạo VM mới trên ESXi, cài Ubuntu Server
2. Cài các package cần thiết:

```bash
sudo apt update
sudo apt install -y open-vm-tools openssh-server
```

3. Tạo user và cho phép sudo:

```bash
sudo adduser youruser
sudo usermod -aG sudo youruser
```

4. Shutdown VM và đặt tên (ví dụ: `template-vm`)

### Sử dụng

#### Terraform - Tạo VM

```bash
cd terraform

# Khởi tạo
terraform init

# Xem trước
terraform plan

# Tạo VM
terraform apply

# Xem IP của VM
terraform output
```

#### Ansible - Config VM

Sau khi Terraform tạo VM xong:

```bash
cd ansible

# Update IP trong inventory/hosts.yml

# Chạy playbook
ansible-playbook playbooks/setup-vm.yml
```

### Thêm VM mới

1. Thêm module trong `terraform/main.tf`:

```hcl
module "redis" {
  source = "./modules/esxi-vm"

  guest_name     = "redis"
  clone_from_vm  = var.clone_from_vm
  disk_store     = var.disk_store
  numvcpus       = 2
  memsize        = 2048
  boot_disk_size = 50
  network        = local.port_groups.db_network
}
```

2. Thêm output trong `terraform/outputs.tf`:

```hcl
output "redis_ip" {
  value = module.redis.vm_ip
}
```

3. Chạy `terraform apply`

---

## English

### Table of Contents

- [Introduction](#introduction)
- [Requirements](#requirements)
- [Project Structure](#project-structure)
- [Installation](#installation)
- [Prepare Template VM](#prepare-template-vm)
- [Usage](#usage)
  - [Terraform - Create VM](#terraform---create-vm)
  - [Ansible - Configure VM](#ansible---configure-vm)
- [Add New VM](#add-new-vm)

### Introduction

This repo manages homelab ESXi server infrastructure as code:

- **Terraform**: Create/destroy VMs on ESXi
- **Ansible**: Configure VMs (hostname, IP, install services)

### Requirements

#### On local machine (macOS/Linux)

| Tool      | Version | Install                                                                                                 |
| --------- | ------- | ------------------------------------------------------------------------------------------------------- |
| Terraform | >= 1.0  | `brew install terraform`                                                                                |
| Ansible   | >= 2.9  | `brew install ansible`                                                                                  |
| OVF Tool  | >= 4.0  | [Download from VMware](https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest) |

#### On ESXi server

- ESXi 6.7+ with SSH enabled
- Datastore with template VM
- Network port groups created

#### On Template VM

- Ubuntu Server 22.04+ (or other distro)
- `open-vm-tools` installed (for Terraform to get IP)
- User with sudo privileges
- SSH enabled

### Project Structure

```
.
├── terraform/
│   ├── main.tf              # Define VMs
│   ├── provider.tf          # ESXi connection
│   ├── variables.tf         # Input variables
│   ├── outputs.tf           # Outputs (VM IPs)
│   ├── locals.tf            # Fixed values (port groups)
│   ├── terraform.tfvars     # Actual values (gitignored)
│   └── modules/
│       └── esxi-vm/         # Reusable module
│
├── ansible/
│   ├── ansible.cfg          # Ansible config
│   ├── inventory/
│   │   └── hosts.yml        # Server list
│   └── playbooks/
│       └── setup-vm.yml     # VM setup playbook
│
└── tools/
    └── ovftool/             # VMware OVF Tool (gitignored)
```

### Installation

#### 1. Clone repo

```bash
git clone <repo-url>
cd homelab-iac
```

#### 2. Install OVF Tool

Download from VMware and extract to `tools/ovftool/`, then:

```bash
# Allow execution (macOS)
xattr -cr tools/ovftool/

# Create symlink
sudo ln -sf "$(pwd)/tools/ovftool/ovftool" /usr/local/bin/ovftool
```

#### 3. Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
esxi_hostname = "192.168.1.50"      # ESXi server IP
esxi_username = "root"
esxi_password = "your-password"
clone_from_vm = "template-vm"       # Template VM name on ESXi
```

#### 4. Configure Ansible

```bash
cd ansible
cp inventory/hosts.yml.example inventory/hosts.yml
```

Edit `inventory/hosts.yml` with VM information.

### Prepare Template VM

Template VM must exist on ESXi. Steps to create:

1. Create new VM on ESXi, install Ubuntu Server
2. Install required packages:

```bash
sudo apt update
sudo apt install -y open-vm-tools openssh-server
```

3. Create user with sudo:

```bash
sudo adduser youruser
sudo usermod -aG sudo youruser
```

4. Shutdown VM and name it (e.g., `template-vm`)

### Usage

#### Terraform - Create VM

```bash
cd terraform

# Initialize
terraform init

# Preview
terraform plan

# Create VM
terraform apply

# View VM IP
terraform output
```

#### Ansible - Configure VM

After Terraform creates VM:

```bash
cd ansible

# Update IP in inventory/hosts.yml

# Run playbook
ansible-playbook playbooks/setup-vm.yml
```

### Add New VM

1. Add module in `terraform/main.tf`:

```hcl
module "redis" {
  source = "./modules/esxi-vm"

  guest_name     = "redis"
  clone_from_vm  = var.clone_from_vm
  disk_store     = var.disk_store
  numvcpus       = 2
  memsize        = 2048
  boot_disk_size = 50
  network        = local.port_groups.db_network
}
```

2. Add output in `terraform/outputs.tf`:

```hcl
output "redis_ip" {
  value = module.redis.vm_ip
}
```

3. Run `terraform apply`
