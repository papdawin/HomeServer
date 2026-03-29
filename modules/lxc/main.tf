locals {
  ssh_keys = [
    for key in split("\n", trimspace(var.ssh_public_keys)) : trimspace(key)
    if trimspace(key) != ""
  ]

  rootfs_size_gb = tonumber(replace(lower(trimspace(var.rootfs_size)), "/[^0-9]/", ""))
}

resource "proxmox_virtual_environment_container" "this" {
  node_name     = var.target_node
  vm_id         = var.vmid
  unprivileged  = var.unprivileged
  started       = var.start
  start_on_boot = var.onboot

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
    swap      = var.swap
  }

  features {
    nesting = var.features_nesting
  }

  disk {
    datastore_id = var.rootfs_storage
    size         = local.rootfs_size_gb
  }

  network_interface {
    name     = "eth0"
    bridge   = var.bridge
    enabled  = true
    firewall = false
  }

  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = trimspace(var.ipv4_cidr)
        gateway = trimspace(var.gateway) != "" ? trimspace(var.gateway) : null
      }
    }

    user_account {
      keys     = length(local.ssh_keys) > 0 ? local.ssh_keys : null
      password = var.lxc_password
    }
  }

  operating_system {
    template_file_id = var.ostemplate
    type             = var.ostype
  }

  wait_for_ip {
    ipv4 = true
  }
}

resource "null_resource" "flake_apply" {
  count = var.flake_file != "" ? 1 : 0

  triggers = {
    container_id = tostring(var.vmid)
    flake_sha    = filesha256(var.flake_file)
    flake_attr   = var.flake_attr
    target_ip    = split("/", trimspace(var.ipv4_cidr))[0]
  }

  connection {
    type     = "ssh"
    host     = split("/", trimspace(var.ipv4_cidr))[0]
    user     = "root"
    agent    = var.bootstrap_use_ssh_agent
    private_key = try(file(pathexpand("~/.ssh/id_ed25519")), try(file(pathexpand("~/.ssh/id_rsa")), null))
    timeout  = "20m"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /etc/nixos",
    ]
  }

  provisioner "file" {
    source      = var.flake_file
    destination = "/etc/nixos/flake.nix"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /etc/nix",
      "grep -q 'experimental-features' /etc/nix/nix.conf || echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf",
      "nixos-rebuild switch --impure --flake /etc/nixos#${var.flake_attr}",
    ]
  }

  depends_on = [proxmox_virtual_environment_container.this]
}
