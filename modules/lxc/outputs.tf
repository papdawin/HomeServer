output "id" {
  value = proxmox_virtual_environment_container.this.id
}

output "hostname" {
  value = var.hostname
}

output "mount_points" {
  value = [
    for mount_point in proxmox_virtual_environment_container.this.mount_point : {
      path              = mount_point.path
      volume            = mount_point.volume
      path_in_datastore = try(mount_point.path_in_datastore, null)
    }
  ]
}
