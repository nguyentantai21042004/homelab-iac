# ===== Postgres VM =====
module "postgres" {
  source = "./modules/esxi-vm"

  guest_name = "postgres"
  ovf_source = var.ovf_source
  disk_store = var.disk_store
  numvcpus   = 3
  memsize    = 6144
  network    = local.port_groups.db_network
}
