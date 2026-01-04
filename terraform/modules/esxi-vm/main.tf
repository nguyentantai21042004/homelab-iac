# Data disk (optional)
resource "esxi_virtual_disk" "data_disk" {
  count = var.data_disk_size > 0 ? 1 : 0

  virtual_disk_disk_store = var.disk_store
  virtual_disk_dir        = var.guest_name
  virtual_disk_name       = "${var.guest_name}-data.vmdk"
  virtual_disk_size       = var.data_disk_size
  virtual_disk_type       = "thin"
}

resource "esxi_guest" "vm" {
  guest_name    = var.guest_name
  disk_store    = var.disk_store
  clone_from_vm = var.clone_from_vm
  numvcpus      = var.numvcpus
  memsize       = var.memsize

  network_interfaces {
    virtual_network = var.network
  }

  # Attach data disk if exists
  dynamic "virtual_disks" {
    for_each = var.data_disk_size > 0 ? [1] : []
    content {
      virtual_disk_id = esxi_virtual_disk.data_disk[0].id
      slot            = "0:1"
    }
  }

  depends_on = [esxi_virtual_disk.data_disk]
}
