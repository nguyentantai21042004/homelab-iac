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

variable "ovf_source" {
  type        = string
  description = "Path to OVF template"
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

variable "network" {
  type        = string
  description = "Port group name"
}
