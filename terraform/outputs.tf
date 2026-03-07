output "master_node_ips" {
  description = "Control-plane node IP addresses"
  value       = { for k, v in module.master_nodes : k => v.ip_address }
}

output "worker_node_ips" {
  description = "Worker node IP addresses"
  value       = { for k, v in module.worker_nodes : k => v.ip_address }
}

output "all_node_ips" {
  description = "All node IPs (masters + workers)"
  value = merge(
    { for k, v in module.master_nodes : k => v.ip_address },
    { for k, v in module.worker_nodes : k => v.ip_address }
  )
}
