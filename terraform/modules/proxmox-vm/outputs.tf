output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.node.vm_id
}

output "ip_address" {
  description = "Node IP (CIDR notation)"
  value       = var.ip_address
}

output "name" {
  description = "VM hostname"
  value       = var.vm_name
}
