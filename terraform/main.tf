# ─────────────────────────────────────────────────────────────
# k8-dev Kubernetes Cluster — Proxmox VM Provisioning
# ─────────────────────────────────────────────────────────────

# ── Control Plane Nodes ──────────────────────────────────────
module "master_nodes" {
  source   = "./modules/proxmox-vm"
  for_each = { for node in var.master_nodes : node.name => node }

  vm_name      = each.value.name
  vm_id        = each.value.vm_id
  proxmox_node = var.proxmox_node
  template_id  = var.template_vm_id
  cores        = var.master_cores
  memory       = var.master_memory_mb
  disk_size    = var.disk_size_gb
  storage      = var.storage_pool
  bridge       = var.network_bridge
  ip_address   = each.value.ip
  gateway      = var.gateway
  dns_servers  = var.dns_servers
  ssh_key      = var.ssh_public_key
  tags         = ["kubernetes", "master", "k8-dev"]
}

# ── Worker Nodes ─────────────────────────────────────────────
module "worker_nodes" {
  source   = "./modules/proxmox-vm"
  for_each = { for node in var.worker_nodes : node.name => node }

  vm_name      = each.value.name
  vm_id        = each.value.vm_id
  proxmox_node = var.proxmox_node
  template_id  = var.template_vm_id
  cores        = var.worker_cores
  memory       = var.worker_memory_mb
  disk_size    = var.disk_size_gb
  storage      = var.storage_pool
  bridge       = var.network_bridge
  ip_address   = each.value.ip
  gateway      = var.gateway
  dns_servers  = var.dns_servers
  ssh_key      = var.ssh_public_key
  tags         = ["kubernetes", "worker", "k8-dev"]
}
