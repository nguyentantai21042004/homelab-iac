# ===== Admin VM (runs Terraform/Ansible) =====
module "admin" {
  source = "./modules/esxi-vm"

  guest_name    = "admin"
  clone_from_vm = var.clone_from_vm
  disk_store    = var.disk_store
  numvcpus      = 2
  memsize       = 2048
  network       = local.port_groups.vm_network
}

# ===== Postgres VM =====
module "postgres" {
  source = "./modules/esxi-vm"

  guest_name     = "postgres"
  clone_from_vm  = var.clone_from_vm
  disk_store     = var.disk_store
  numvcpus       = 3
  memsize        = 6144 # 6GB RAM
  data_disk_size = 100  # 100GB data disk
  network        = local.port_groups.db_network
}

# ===== Object Storage VM (MinIO + Zot Registry) =====
module "storage" {
  source = "./modules/esxi-vm"

  guest_name     = "storage"
  clone_from_vm  = var.clone_from_vm
  disk_store     = var.disk_store
  numvcpus       = 3
  memsize        = 6144 # 6GB RAM
  data_disk_size = 100  # 100GB data disk
  network        = local.port_groups.prod_network
}

# ===== API Gateway VM (Traefik) =====
module "api_gateway" {
  source = "./modules/esxi-vm"

  guest_name    = "api-gateway"
  clone_from_vm = var.clone_from_vm
  disk_store    = var.disk_store
  numvcpus      = 2
  memsize       = 2048 # 2GB RAM
  network       = local.port_groups.vm_network
}
