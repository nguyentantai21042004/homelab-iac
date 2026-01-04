resource "esxi_guest" "vm" {
  guest_name     = var.guest_name
  disk_store     = var.disk_store
  clone_from_vm  = var.clone_from_vm
  numvcpus       = var.numvcpus
  memsize        = var.memsize
  boot_disk_size = var.boot_disk_size > 0 ? var.boot_disk_size : null

  network_interfaces {
    virtual_network = var.network
  }
}
