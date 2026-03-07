# ─────────────────────────────────────────────────────────────
# Module: proxmox-vm
# Clones a cloud-init template and configures it as a K8s node
# ─────────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_vm" "node" {
  name      = var.vm_name
  node_name = var.proxmox_node
  vm_id     = var.vm_id

  # ── Source Template ────────────────────────────────────────
  clone {
    vm_id   = var.template_id
    full    = true
    retries = 3
  }

  # ── Guest Agent ────────────────────────────────────────────
  agent {
    enabled = true
    trim    = true
  }

  # ── CPU ────────────────────────────────────────────────────
  cpu {
    cores = var.cores
    type  = "x86-64-v2-AES"
  }

  # ── Memory ─────────────────────────────────────────────────
  memory {
    dedicated = var.memory
  }

  # ── Boot Disk ──────────────────────────────────────────────
  disk {
    datastore_id = var.storage
    size         = var.disk_size
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    cache        = "writethrough"
  }

  # ── Network ────────────────────────────────────────────────
  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  # ── Cloud-Init ─────────────────────────────────────────────
  initialization {
    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_key]
    }
  }

  # ── OS Hint ────────────────────────────────────────────────
  operating_system {
    type = "l26"
  }

  tags = var.tags

  # ── Start after provisioning ───────────────────────────────
  started = true

  lifecycle {
    # Prevent drift on cloud-init after initial apply
    ignore_changes = [initialization]
  }
}
