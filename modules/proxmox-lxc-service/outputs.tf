output "node_enabled" {
  description = "Whether this Proxmox node is enabled."
  value       = var.proxmox_node.enabled
}

output "container_vm_ids" {
  description = "Container VMIDs keyed by logical container name."
  value       = { for name, mod in module.containers : name => mod.container_vm_id }
}

output "container_ipv4" {
  description = "Container IPv4 info keyed by logical container name."
  value       = { for name, mod in module.containers : name => mod.container_ipv4 }
}
