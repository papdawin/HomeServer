resource "proxmox_virtual_environment_download_file" "lxc_template" {
  count = var.proxmox_node.enabled ? 1 : 0

  content_type = "vztmpl"
  datastore_id = var.lxc_defaults.template_datastore
  file_name    = var.lxc_defaults.template_file_name
  node_name    = var.proxmox_node.name
  url          = var.lxc_defaults.template_url

  checksum           = trimspace(var.lxc_defaults.template_checksum) == "" ? null : var.lxc_defaults.template_checksum
  checksum_algorithm = trimspace(var.lxc_defaults.template_checksum) == "" ? null : "sha256"
  overwrite          = false
}

locals {
  enabled_containers = {
    for name, container in var.containers :
    name => container
    if var.proxmox_node.enabled && try(container.enabled, true)
  }
}

module "containers" {
  for_each = local.enabled_containers

  source = "../lxc-container"

  node_name        = var.proxmox_node.name
  ct_id            = each.value.ct_id
  hostname         = each.value.hostname
  description      = coalesce(try(each.value.description, null), "LXC managed by Terraform/Terragrunt")
  start_on_boot    = var.lxc_defaults.start_on_boot
  started          = var.lxc_defaults.started
  unprivileged     = var.lxc_defaults.unprivileged
  protection       = var.lxc_defaults.protection
  tags             = distinct(concat(var.lxc_defaults.tags, try(each.value.tags, [])))
  template_file_id = proxmox_virtual_environment_download_file.lxc_template[0].id

  rootfs_datastore = coalesce(try(each.value.rootfs_datastore, null), var.lxc_defaults.rootfs_datastore_default)
  rootfs_size_gb   = coalesce(try(each.value.rootfs_size_gb, null), var.lxc_defaults.rootfs_size_gb_default)

  cpu_cores = coalesce(try(each.value.cpu_cores, null), var.lxc_defaults.cpu_cores_default)
  cpu_units = var.lxc_defaults.cpu_units
  cpu_limit = var.lxc_defaults.cpu_limit

  memory_mb = coalesce(try(each.value.memory_mb, null), var.lxc_defaults.memory_mb_default)
  swap_mb   = var.lxc_defaults.swap_mb

  network = {
    interface     = "veth0"
    bridge        = var.network.bridge
    ipv4_cidr     = each.value.static_ipv4_cidr
    ipv4_gateway  = var.network.gateway_ipv4
    firewall      = var.network.firewall
    vlan_id       = try(var.network.vlan_id, null)
    mtu           = try(var.network.mtu, null)
    rate_limit_mb = try(var.network.rate_limit_mb, null)
    dns_servers   = var.network.dns_servers
    dns_search    = var.network.dns_search
  }

  startup = {
    order      = var.lxc_defaults.startup_order
    up_delay   = var.lxc_defaults.startup_up_delay
    down_delay = var.lxc_defaults.startup_down_delay
  }

  ssh_public_keys    = try(each.value.ssh_public_keys, [])
  user_password      = try(each.value.user_password, null)
  bootstrap_commands = try(each.value.bootstrap_commands, [])
  mount_points       = try(each.value.mount_points, [])
  device_passthrough = try(each.value.device_passthrough, [])
}
