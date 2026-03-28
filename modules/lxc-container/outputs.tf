output "container_vm_id" {
  description = "Container VMID."
  value       = proxmox_virtual_environment_container.this.vm_id
}

output "container_id" {
  description = "Provider container resource ID."
  value       = proxmox_virtual_environment_container.this.id
}

output "container_ipv4" {
  description = "Container IPv4 values per interface."
  value       = proxmox_virtual_environment_container.this.ipv4
}

