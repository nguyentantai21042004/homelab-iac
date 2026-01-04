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
variable "ovf_source" {
  type        = string
  description = "Path to OVF template"
}

variable "disk_store" {
  type    = string
  default = "datastore1"
}
