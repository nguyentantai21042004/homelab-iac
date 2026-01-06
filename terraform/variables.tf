# ===== ESXi Connection =====
variable "esxi_hostname" {
  type        = string
  description = "ESXi server IP/hostname"
}

variable "esxi_username" {
  type    = string
  default = "root"
}

variable "esxi_password" {
  type      = string
  sensitive = true
}

variable "esxi_hostport" {
  type        = number
  default     = 22
  description = "ESXi SSH port"
}

# ===== Shared VM Config =====
variable "clone_from_vm" {
  type        = string
  description = "Name of VM to clone from"
}

variable "disk_store" {
  type    = string
  default = "datastore1"
}

# ===== K3s Cluster Config =====
variable "k3s_node_count" {
  type        = number
  default     = 3
  description = "Number of K3s cluster nodes"
}

variable "k3s_vm_specs" {
  type = object({
    cpu = number
    ram = number
  })
  default = {
    cpu = 4
    ram = 8192 # 8GB (Rancher + Longhorn + headroom)
  }
  description = "K3s node VM specifications"
}
