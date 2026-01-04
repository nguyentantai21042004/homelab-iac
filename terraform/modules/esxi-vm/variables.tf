# VM Configuration
variable "guest_name" {
  type        = string
  description = "Name of the VM"
}

variable "disk_store" {
  type        = string
  default     = "datastore1"
  description = "ESXi datastore name"
}

variable "clone_from_vm" {
  type        = string
  description = "Name of existing VM to clone from"
}

variable "numvcpus" {
  type        = number
  default     = 2
  description = "Number of vCPUs"
}

variable "memsize" {
  type        = number
  default     = 2048
  description = "Memory in MB"
}

variable "boot_disk_size" {
  type        = number
  default     = 0
  description = "Boot disk size in GB (0 = keep template size)"
}

variable "network" {
  type        = string
  description = "Port group name"
}
