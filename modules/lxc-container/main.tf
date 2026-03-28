terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_virtual_environment_container" "this" {
  node_name = var.node_name
  vm_id     = var.ct_id

  description   = var.description
  start_on_boot = var.start_on_boot
  started       = var.started
  unprivileged  = var.unprivileged
  protection    = var.protection
  tags          = var.tags

  operating_system {
    template_file_id = var.template_file_id
    type             = "ubuntu"
  }

  cpu {
    cores = var.cpu_cores
    units = var.cpu_units
  }

  memory {
    dedicated = var.memory_mb
    swap      = var.swap_mb
  }

  disk {
    datastore_id = var.rootfs_datastore
    size         = var.rootfs_size_gb
  }

  startup {
    order      = var.startup.order
    up_delay   = var.startup.up_delay
    down_delay = var.startup.down_delay
  }

  features {
    nesting = false
    keyctl  = false
    fuse    = false
    mount   = []
  }

  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = var.network.ipv4_cidr
        gateway = var.network.ipv4_gateway
      }
    }

    dns {
      domain  = var.network.dns_search
      servers = var.network.dns_servers
    }

    user_account {
      keys     = var.ssh_public_keys
      password = var.user_password
    }
  }

  network_interface {
    name       = var.network.interface
    bridge     = var.network.bridge
    firewall   = var.network.firewall
    vlan_id    = try(var.network.vlan_id, null)
    mtu        = try(var.network.mtu, null)
    rate_limit = try(var.network.rate_limit_mb, null)
  }

  dynamic "mount_point" {
    for_each = var.mount_points
    content {
      path          = mount_point.value.path
      volume        = mount_point.value.volume
      size          = try(mount_point.value.size, null)
      read_only     = try(mount_point.value.read_only, null)
      backup        = try(mount_point.value.backup, null)
      replicate     = try(mount_point.value.replicate, null)
      shared        = try(mount_point.value.shared, null)
      mount_options = try(mount_point.value.mount_options, null)
    }
  }

  dynamic "device_passthrough" {
    for_each = var.device_passthrough
    content {
      path       = device_passthrough.value.path
      uid        = try(device_passthrough.value.uid, null)
      gid        = try(device_passthrough.value.gid, null)
      mode       = try(device_passthrough.value.mode, null)
      deny_write = try(device_passthrough.value.deny_write, null)
    }
  }

  wait_for_ip {
    ipv4 = true
  }

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "null_resource" "bootstrap" {
  count = length(var.bootstrap_commands) > 0 ? 1 : 0

  triggers = {
    container_id = proxmox_virtual_environment_container.this.id
    commands     = join("\n", var.bootstrap_commands)
    target_ip    = split("/", var.network.ipv4_cidr)[0]
  }

  connection {
    type     = "ssh"
    host     = split("/", var.network.ipv4_cidr)[0]
    user     = "root"
    password = var.user_password
    timeout  = "10m"
  }

  provisioner "remote-exec" {
    inline = var.bootstrap_commands
  }

  lifecycle {
    precondition {
      condition     = var.user_password != null
      error_message = "bootstrap_commands requires user_password for SSH provisioning."
    }
  }

  depends_on = [proxmox_virtual_environment_container.this]
}
