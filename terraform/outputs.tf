output "admin_ip" {
  value = module.admin.vm_ip
}

output "postgres_ip" {
  value = module.postgres.vm_ip
}

output "storage_ip" {
  value = module.storage.vm_ip
}

output "api_gateway_ip" {
  value = module.api_gateway.vm_ip
}

output "k3s_ips" {
  value       = [for node in module.k3s_nodes : node.vm_ip]
  description = "K3s cluster node IPs"
}

output "localstack_ip" {
  value = module.localstack.vm_ip
}

output "cicd_ip" {
  value = module.cicd.vm_ip
}
