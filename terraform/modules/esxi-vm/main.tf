resource "esxi_guest" "vm" {
  guest_name = var.guest_name
  disk_store = var.disk_store
  ovf_source = var.ovf_source
  numvcpus   = var.numvcpus
  memsize    = var.memsize

  network_interfaces {
    virtual_network = var.network
  }
}
