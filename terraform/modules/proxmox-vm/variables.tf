variable "vm_name"      { type = string }
variable "vm_id"        { type = number }
variable "proxmox_node" { type = string }
variable "template_id"  { type = number }
variable "cores"        { type = number }
variable "memory"       { type = number }
variable "disk_size"    { type = number }
variable "storage"      { type = string }
variable "bridge"       { type = string }
variable "ip_address"   { type = string }
variable "gateway"      { type = string }
variable "ssh_key"      { type = string }
variable "dns_servers"  { type = list(string) }

variable "tags" {
  type    = list(string)
  default = []
}
