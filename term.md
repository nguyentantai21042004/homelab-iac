## Tổng quan cấu trúc

```
terraform/
├── provider.tf          # Kết nối ESXi
├── variables.tf         # Input từ user (credentials, template)
├── locals.tf            # Giá trị cố định (port groups)
├── main.tf              # Định nghĩa các VMs
├── outputs.tf           # Output sau khi tạo (IP addresses)
├── terraform.tfvars     # Giá trị thật (gitignored)
│
└── modules/esxi-vm/     # Module tái sử dụng
    ├── main.tf          # Resource esxi_guest
    ├── variables.tf     # Input cho module
    ├── outputs.tf       # Output từ module
    └── providers.tf     # Khai báo provider dependency
```

## Vai trò từng file

| File                | Vai trò                                  |
| ------------------- | ---------------------------------------- |
| `provider.tf`       | Khai báo & kết nối đến ESXi server       |
| `variables.tf`      | Định nghĩa input cần user cung cấp       |
| `locals.tf`         | Giá trị cố định biết trước (port groups) |
| `main.tf`           | Gọi module để tạo VMs                    |
| `outputs.tf`        | Xuất thông tin sau khi tạo (IP)          |
| `modules/esxi-vm/*` | Template tái sử dụng cho mọi VM          |

---

## Cách thêm VM mới

Thêm block module trong `main.tf`:

```hcl
# ===== Redis VM =====
module "redis" {
  source = "./modules/esxi-vm"

  guest_name = "redis-prod-01"
  ovf_source = var.ovf_source
  disk_store = var.disk_store
  numvcpus   = 2
  memsize    = 2048
  network    = local.port_groups.db_network
}

# ===== Backend VM =====
module "backend" {
  source = "./modules/esxi-vm"

  guest_name = "backend-prod-01"
  ovf_source = var.ovf_source
  disk_store = var.disk_store
  numvcpus   = 4
  memsize    = 8192
  network    = local.port_groups.prod_network
}
```

Và thêm output trong `outputs.tf`:

```hcl
output "redis_ip" {
  value = module.redis.vm_ip
}
```

---

## Config chi tiết cho từng loại VM

Nếu cần config khác nhau (ví dụ: thêm disk, nhiều NIC), mở rộng module:

**`modules/esxi-vm/variables.tf`** - thêm biến:

```hcl
variable "virtual_disks" {
  type = list(object({
    virtual_disk_id = string
    slot            = string
  }))
  default     = []
  description = "Additional disks"
}
```

**`modules/esxi-vm/main.tf`** - dùng dynamic block:

```hcl
resource "esxi_guest" "vm" {
  # ... existing config ...

  dynamic "virtual_disks" {
    for_each = var.virtual_disks
    content {
      virtual_disk_id = virtual_disks.value.virtual_disk_id
      slot            = virtual_disks.value.slot
    }
  }
}
```

**`main.tf`** - truyền config:

```hcl
module "postgres" {
  source = "./modules/esxi-vm"
  # ...
  virtual_disks = [
    { virtual_disk_id = "data-disk-100gb", slot = "0:1" }
  ]
}
```

---

Cấu trúc hiện tại đã clean và scalable. Muốn tôi thêm VM nào cụ thể không?
