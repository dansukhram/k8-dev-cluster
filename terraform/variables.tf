# ── Proxmox Connection ───────────────────────────────────────
variable "proxmox_endpoint" {
  description = "Proxmox VE API URL (e.g. https://172.16.1.2:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token: 'user@realm!tokenid=secret'"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name to provision VMs on"
  type        = string
}

variable "template_vm_id" {
  description = "VM ID of the Ubuntu 24.04 cloud-init template"
  type        = number
}

# ── Node Definitions ─────────────────────────────────────────
variable "master_nodes" {
  description = "Control-plane node configurations"
  type = list(object({
    name = string
    vm_id = number
    ip    = string
  }))
}

variable "worker_nodes" {
  description = "Worker node configurations"
  type = list(object({
    name = string
    vm_id = number
    ip    = string
  }))
}

# ── Node Specs ───────────────────────────────────────────────
variable "master_cores" {
  description = "vCPU count for master nodes"
  type        = number
  default     = 2
}

variable "master_memory_mb" {
  description = "Memory in MB for master nodes"
  type        = number
  default     = 4096
}

variable "worker_cores" {
  description = "vCPU count for worker nodes"
  type        = number
  default     = 2
}

variable "worker_memory_mb" {
  description = "Memory in MB for worker nodes"
  type        = number
  default     = 4096
}

variable "disk_size_gb" {
  description = "Disk size in GB for all nodes"
  type        = number
  default     = 50
}

# ── Network ──────────────────────────────────────────────────
variable "network_bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

variable "storage_pool" {
  description = "Proxmox storage pool for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "gateway" {
  description = "Default gateway for node IPs"
  type        = string
}

variable "dns_servers" {
  description = "DNS server list"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "ssh_public_key" {
  description = "SSH public key injected via cloud-init"
  type        = string
}
