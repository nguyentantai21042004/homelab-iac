# Hướng dẫn thêm VM mới / Add New VM Guide

**Ngôn ngữ / Language:** [Tiếng Việt](#tiếng-việt) | [English](#english)

---

## Tiếng Việt

### Mục lục

- [Tổng quan quy trình](#tổng-quan-quy-trình)
- [Bước 1: Thêm Terraform module](#bước-1-thêm-terraform-module)
- [Bước 2: Thêm Ansible inventory](#bước-2-thêm-ansible-inventory)
- [Bước 3: Tạo VM](#bước-3-tạo-vm)
- [Bước 4: Config VM](#bước-4-config-vm)
- [Ví dụ cụ thể](#ví-dụ-cụ-thể)
- [Tham số VM Module](#tham-số-vm-module)
- [Cấu hình nâng cao](#cấu-hình-nâng-cao)

---

### Tổng quan quy trình

```
┌─────────────────────────────────────────────────────────────────┐
│                     THÊM VM MỚI                                 │
│                                                                 │
│  1. TERRAFORM                    2. ANSIBLE                     │
│  ┌─────────────────┐             ┌─────────────────┐            │
│  │ main.tf         │             │ hosts.yml       │            │
│  │ - Thêm module   │             │ - Thêm host     │            │
│  │ - CPU/RAM/Disk  │             │ - IP/User       │            │
│  │ - Network       │             │ - Variables     │            │
│  └────────┬────────┘             └────────┬────────┘            │
│           │                               │                     │
│           ▼                               ▼                     │
│  ┌─────────────────┐             ┌─────────────────┐            │
│  │ outputs.tf      │             │ playbooks/      │            │
│  │ - Thêm output   │             │ - setup-vm.yml  │            │
│  │   cho IP        │             │ - (custom).yml  │            │
│  └────────┬────────┘             └────────┬────────┘            │
│           │                               │                     │
│           ▼                               ▼                     │
│  ┌─────────────────────────────────────────────────┐            │
│  │              terraform apply                    │            │
│  │              ansible-playbook                   │            │
│  └─────────────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

---

### Bước 1: Thêm Terraform module

Mở `terraform/main.tf` và thêm module mới:

```hcl
module "ten-vm" {
  source = "./modules/esxi-vm"

  guest_name     = "ten-vm"           # Tên VM trên ESXi
  clone_from_vm  = var.clone_from_vm  # Template VM
  disk_store     = var.disk_store     # Datastore
  numvcpus       = 2                  # Số CPU
  memsize        = 4096               # RAM (MB)
  data_disk_size = 50                 # Data disk (GB), 0 = không có
  network        = local.port_groups.db_network  # Port group
}
```

Thêm output trong `terraform/outputs.tf`:

```hcl
output "ten_vm_ip" {
  value = module.ten-vm.vm_ip
}
```

---

### Bước 2: Thêm Ansible inventory

Mở `ansible/inventory/hosts.yml`:

```yaml
all:
  children:
    # Group mới hoặc thêm vào group có sẵn
    ten_vm_servers:
      hosts:
        ten-vm:
          ansible_host: 172.16.19.xxx # IP tạm (DHCP) hoặc static
          ansible_user: tantai

          # Variables cho setup-vm.yml
          vm_hostname: "ten-vm"
          static_ip: "172.16.19.10/24" # IP static muốn set
          gateway: "172.16.19.1"

          # Data disk (nếu có)
          data_disk_device: "/dev/sdb"
          data_mount_point: "/data"
```

---

### Bước 3: Tạo VM

```bash
# Sync code (nếu dùng Mutagen)
./scripts/sync-start.sh 192.168.1.100 tantai

# Preview
terraform plan

# Tạo VM từ Admin VM (nhanh)
./scripts/remote-apply.sh 192.168.1.100 tantai

# Hoặc từ local (chậm)
cd terraform && terraform apply
```

---

### Bước 4: Config VM

```bash
cd ansible

# Lấy IP từ terraform output, update vào hosts.yml

# Chạy setup cơ bản (hostname, static IP, mount disk)
ansible-playbook playbooks/setup-vm.yml -l ten-vm

# Chạy playbook riêng (nếu có)
ansible-playbook playbooks/setup-ten-vm.yml
```

---

### Ví dụ cụ thể

#### Ví dụ 1: PostgreSQL Server

**terraform/main.tf:**

```hcl
module "postgres" {
  source = "./modules/esxi-vm"

  guest_name     = "postgres"
  clone_from_vm  = var.clone_from_vm
  disk_store     = var.disk_store
  numvcpus       = 4
  memsize        = 8192              # 8GB RAM
  data_disk_size = 100               # 100GB cho data
  network        = local.port_groups.db_network
}
```

**terraform/outputs.tf:**

```hcl
output "postgres_ip" {
  value = module.postgres.vm_ip
}
```

**ansible/inventory/hosts.yml:**

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
      data_mount_point: "/var/lib/postgresql"

      # Custom variables cho postgres playbook
      postgres_version: "15"
      postgres_max_connections: 200
```

**ansible/playbooks/setup-postgres.yml:**

```yaml
---
- name: Setup PostgreSQL Server
  hosts: postgres_servers
  become: yes

  tasks:
    - name: Install PostgreSQL
      apt:
        name:
          - postgresql-{{ postgres_version }}
          - postgresql-contrib-{{ postgres_version }}
        state: present
        update_cache: yes

    - name: Configure PostgreSQL
      template:
        src: templates/postgresql.conf.j2
        dest: /etc/postgresql/{{ postgres_version }}/main/postgresql.conf
      notify: Restart PostgreSQL

  handlers:
    - name: Restart PostgreSQL
      service:
        name: postgresql
        state: restarted
```

#### Ví dụ 2: Redis Server (không cần data disk)

**terraform/main.tf:**

```hcl
module "redis" {
  source = "./modules/esxi-vm"

  guest_name     = "redis"
  clone_from_vm  = var.clone_from_vm
  disk_store     = var.disk_store
  numvcpus       = 2
  memsize        = 4096
  data_disk_size = 0                 # Không cần data disk
  network        = local.port_groups.db_network
}
```

#### Ví dụ 3: Web Server trên Prod Network

**terraform/main.tf:**

```hcl
module "web" {
  source = "./modules/esxi-vm"

  guest_name     = "web-prod-01"
  clone_from_vm  = var.clone_from_vm
  disk_store     = var.disk_store
  numvcpus       = 2
  memsize        = 2048
  data_disk_size = 0
  network        = local.port_groups.prod_network  # Prod network
}
```

---

### Tham số VM Module

| Tham số        | Kiểu   | Mặc định   | Mô tả                        |
| -------------- | ------ | ---------- | ---------------------------- |
| guest_name     | string | (required) | Tên VM trên ESXi             |
| clone_from_vm  | string | (required) | Tên template VM              |
| disk_store     | string | datastore1 | Tên datastore                |
| numvcpus       | number | 2          | Số vCPU                      |
| memsize        | number | 2048       | RAM (MB)                     |
| data_disk_size | number | 0          | Data disk (GB), 0 = không có |
| network        | string | (required) | Port group name              |

---

### Cấu hình nâng cao

#### Thêm Port Group mới

Sửa `terraform/locals.tf`:

```hcl
locals {
  port_groups = {
    vm_network   = "VM Network"
    db_network   = "DB-Network"
    prod_network = "Prod-Network"
    dev_network  = "Dev-Network"      # Thêm mới
  }
}
```

#### Tạo nhiều VM cùng lúc

```hcl
# terraform/main.tf
module "web" {
  source   = "./modules/esxi-vm"
  for_each = toset(["web-01", "web-02", "web-03"])

  guest_name    = each.key
  clone_from_vm = var.clone_from_vm
  disk_store    = var.disk_store
  numvcpus      = 2
  memsize       = 2048
  network       = local.port_groups.prod_network
}

# terraform/outputs.tf
output "web_ips" {
  value = { for k, v in module.web : k => v.vm_ip }
}
```

#### Ansible: Chạy playbook cho group

```bash
# Chạy cho tất cả postgres servers
ansible-playbook playbooks/setup-postgres.yml

# Chạy cho tất cả hosts
ansible-playbook playbooks/setup-vm.yml

# Chạy cho host cụ thể
ansible-playbook playbooks/setup-vm.yml -l postgres
```

---

## English

### Table of Contents

- [Process Overview](#process-overview)
- [Step 1: Add Terraform module](#step-1-add-terraform-module)
- [Step 2: Add Ansible inventory](#step-2-add-ansible-inventory)
- [Step 3: Create VM](#step-3-create-vm)
- [Step 4: Configure VM](#step-4-configure-vm)
- [Specific Examples](#specific-examples)
- [VM Module Parameters](#vm-module-parameters)
- [Advanced Configuration](#advanced-configuration)

---

### Process Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     ADD NEW VM                                  │
│                                                                 │
│  1. TERRAFORM                    2. ANSIBLE                     │
│  ┌─────────────────┐             ┌─────────────────┐            │
│  │ main.tf         │             │ hosts.yml       │            │
│  │ - Add module    │             │ - Add host      │            │
│  │ - CPU/RAM/Disk  │             │ - IP/User       │            │
│  │ - Network       │             │ - Variables     │            │
│  └────────┬────────┘             └────────┬────────┘            │
│           │                               │                     │
│           ▼                               ▼                     │
│  ┌─────────────────┐             ┌─────────────────┐            │
│  │ outputs.tf      │             │ playbooks/      │            │
│  │ - Add output    │             │ - setup-vm.yml  │            │
│  │   for IP        │             │ - (custom).yml  │            │
│  └────────┬────────┘             └────────┬────────┘            │
│           │                               │                     │
│           ▼                               ▼                     │
│  ┌─────────────────────────────────────────────────┐            │
│  │              terraform apply                    │            │
│  │              ansible-playbook                   │            │
│  └─────────────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

---

### Step 1: Add Terraform module

Open `terraform/main.tf` and add new module:

```hcl
module "vm-name" {
  source = "./modules/esxi-vm"

  guest_name     = "vm-name"          # VM name on ESXi
  clone_from_vm  = var.clone_from_vm  # Template VM
  disk_store     = var.disk_store     # Datastore
  numvcpus       = 2                  # CPU count
  memsize        = 4096               # RAM (MB)
  data_disk_size = 50                 # Data disk (GB), 0 = none
  network        = local.port_groups.db_network  # Port group
}
```

Add output in `terraform/outputs.tf`:

```hcl
output "vm_name_ip" {
  value = module.vm-name.vm_ip
}
```

---

### Step 2: Add Ansible inventory

Open `ansible/inventory/hosts.yml`:

```yaml
all:
  children:
    # New group or add to existing
    vm_name_servers:
      hosts:
        vm-name:
          ansible_host: 172.16.19.xxx # Temp IP (DHCP) or static
          ansible_user: tantai

          # Variables for setup-vm.yml
          vm_hostname: "vm-name"
          static_ip: "172.16.19.10/24" # Desired static IP
          gateway: "172.16.19.1"

          # Data disk (if any)
          data_disk_device: "/dev/sdb"
          data_mount_point: "/data"
```

---

### Step 3: Create VM

```bash
# Sync code (if using Mutagen)
./scripts/sync-start.sh 192.168.1.100 tantai

# Preview
terraform plan

# Create VM from Admin VM (fast)
./scripts/remote-apply.sh 192.168.1.100 tantai

# Or from local (slow)
cd terraform && terraform apply
```

---

### Step 4: Configure VM

```bash
cd ansible

# Get IP from terraform output, update hosts.yml

# Run basic setup (hostname, static IP, mount disk)
ansible-playbook playbooks/setup-vm.yml -l vm-name

# Run custom playbook (if any)
ansible-playbook playbooks/setup-vm-name.yml
```

---

### Specific Examples

#### Example 1: PostgreSQL Server

**terraform/main.tf:**

```hcl
module "postgres" {
  source = "./modules/esxi-vm"

  guest_name     = "postgres"
  clone_from_vm  = var.clone_from_vm
  disk_store     = var.disk_store
  numvcpus       = 4
  memsize        = 8192              # 8GB RAM
  data_disk_size = 100               # 100GB for data
  network        = local.port_groups.db_network
}
```

**terraform/outputs.tf:**

```hcl
output "postgres_ip" {
  value = module.postgres.vm_ip
}
```

**ansible/inventory/hosts.yml:**

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
      data_mount_point: "/var/lib/postgresql"

      # Custom variables for postgres playbook
      postgres_version: "15"
      postgres_max_connections: 200
```

#### Example 2: Redis Server (no data disk)

**terraform/main.tf:**

```hcl
module "redis" {
  source = "./modules/esxi-vm"

  guest_name     = "redis"
  clone_from_vm  = var.clone_from_vm
  disk_store     = var.disk_store
  numvcpus       = 2
  memsize        = 4096
  data_disk_size = 0                 # No data disk
  network        = local.port_groups.db_network
}
```

#### Example 3: Web Server on Prod Network

**terraform/main.tf:**

```hcl
module "web" {
  source = "./modules/esxi-vm"

  guest_name     = "web-prod-01"
  clone_from_vm  = var.clone_from_vm
  disk_store     = var.disk_store
  numvcpus       = 2
  memsize        = 2048
  data_disk_size = 0
  network        = local.port_groups.prod_network  # Prod network
}
```

---

### VM Module Parameters

| Parameter      | Type   | Default    | Description              |
| -------------- | ------ | ---------- | ------------------------ |
| guest_name     | string | (required) | VM name on ESXi          |
| clone_from_vm  | string | (required) | Template VM name         |
| disk_store     | string | datastore1 | Datastore name           |
| numvcpus       | number | 2          | vCPU count               |
| memsize        | number | 2048       | RAM (MB)                 |
| data_disk_size | number | 0          | Data disk (GB), 0 = none |
| network        | string | (required) | Port group name          |

---

### Advanced Configuration

#### Add new Port Group

Edit `terraform/locals.tf`:

```hcl
locals {
  port_groups = {
    vm_network   = "VM Network"
    db_network   = "DB-Network"
    prod_network = "Prod-Network"
    dev_network  = "Dev-Network"      # New
  }
}
```

#### Create multiple VMs at once

```hcl
# terraform/main.tf
module "web" {
  source   = "./modules/esxi-vm"
  for_each = toset(["web-01", "web-02", "web-03"])

  guest_name    = each.key
  clone_from_vm = var.clone_from_vm
  disk_store    = var.disk_store
  numvcpus      = 2
  memsize       = 2048
  network       = local.port_groups.prod_network
}

# terraform/outputs.tf
output "web_ips" {
  value = { for k, v in module.web : k => v.vm_ip }
}
```

#### Ansible: Run playbook for group

```bash
# Run for all postgres servers
ansible-playbook playbooks/setup-postgres.yml

# Run for all hosts
ansible-playbook playbooks/setup-vm.yml

# Run for specific host
ansible-playbook playbooks/setup-vm.yml -l postgres
```
