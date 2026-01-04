# ===== Postgres VM =====
module "postgres" {
  source = "./modules/esxi-vm"

  guest_name     = "postgres"
  clone_from_vm  = var.clone_from_vm
  disk_store     = var.disk_store
  numvcpus       = 3
  memsize        = 6144
  boot_disk_size = 100
  network        = local.port_groups.db_network
}
