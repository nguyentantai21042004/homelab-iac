output "admin_ip" {
  value = module.admin.vm_ip
}

output "postgres_ip" {
  value = module.postgres.vm_ip
}

output "storage_ip" {
  value = module.storage.vm_ip
}
