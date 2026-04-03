resource "proxmox_virtual_environment_storage_directory" "this" {
  id            = trimspace(var.storage_id)
  path          = trimspace(var.path)
  nodes         = var.nodes
  content       = var.content_types
  shared        = var.shared
  disable       = var.disable
  preallocation = trimspace(var.preallocation) != "" ? trimspace(var.preallocation) : null

  lifecycle {
    prevent_destroy = true
  }
}
