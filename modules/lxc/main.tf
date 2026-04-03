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

  dynamic "mount_point" {
    for_each = var.mount_points

    content {
      path   = trimspace(mount_point.value.path)
      volume = trimspace(mount_point.value.volume)
      size = (
        try(mount_point.value.size, null) == null ||
        trimspace(try(mount_point.value.size, "")) == ""
      ) ? null : trimspace(mount_point.value.size)
    }
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
    container_id      = tostring(var.vmid)
    flake_sha         = filesha256(var.flake_file)
    common_sops_sha   = filesha256(var.common_sops_file)
    bootstrap_key_sha = filesha256(pathexpand(var.bootstrap_private_key_file))
    flake_attr        = var.flake_attr
    target_ip         = split("/", trimspace(var.ipv4_cidr))[0]
  }

  connection {
    type        = "ssh"
    host        = split("/", trimspace(var.ipv4_cidr))[0]
    user        = "root"
    agent       = var.bootstrap_use_ssh_agent
    private_key = try(file(pathexpand(var.bootstrap_private_key_file)), try(file(pathexpand("~/.ssh/id_rsa")), null))
    timeout     = "20m"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /etc/nixos",
      "mkdir -p /etc/nixos/secrets",
    ]
  }

  provisioner "file" {
    source      = var.flake_file
    destination = "/etc/nixos/flake.nix"
  }

  provisioner "file" {
    source      = var.common_sops_file
    destination = "/etc/nixos/secrets/common.sops.yaml"
  }

  provisioner "file" {
    source      = pathexpand(var.bootstrap_private_key_file)
    destination = "/etc/nixos/secrets/bootstrap-ssh-private-key"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 700 /etc/nixos/secrets",
      "chmod 600 /etc/nixos/secrets/bootstrap-ssh-private-key /etc/nixos/secrets/common.sops.yaml",
      "mkdir -p /etc/nix",
      "bash -lc 'if [ -w /etc/nix ] && { [ ! -e /etc/nix/nix.conf ] || [ -w /etc/nix/nix.conf ]; }; then grep -q \"experimental-features\" /etc/nix/nix.conf 2>/dev/null || echo \"experimental-features = nix-command flakes\" >> /etc/nix/nix.conf; fi'",
      "bash -lc 'set -euxo pipefail; nixos-rebuild switch --impure --flake /etc/nixos#${var.flake_attr} -L --show-trace 2>&1 | tee /tmp/nixos-rebuild-${var.flake_attr}.log'",
    ]
  }

  depends_on = [proxmox_virtual_environment_container.this]
}
