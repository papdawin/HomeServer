include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}//modules/proxmox-lxc-service"
}

locals {
  node_config  = read_terragrunt_config(find_in_parent_folders("config/node.hcl"))
  secrets_file = "${get_terragrunt_dir()}/secrets.sops.yaml"
  service_secrets = merge(
    {
      ssh_public_keys = []
      user_password   = null
    },
    try(yamldecode(sops_decrypt_file(local.secrets_file)), {})
  )
}

inputs = merge(
  local.node_config.inputs,
  {
    lxc_defaults = merge(local.node_config.inputs.lxc_defaults, {
      unprivileged           = true
      rootfs_size_gb_default = 16
      template_file_name     = "ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
      template_url           = "http://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    })

    containers = {
      jellyfin = {
        ct_id            = 125
        hostname         = "jellyfin"
        static_ipv4_cidr = "192.168.68.25/24"
        tags             = ["media", "jellyfin"]
        ssh_public_keys  = try(local.service_secrets.ssh_public_keys, [])
        user_password    = try(local.service_secrets.user_password, null)
        bootstrap_commands = [
          "set -eux",
          "apt-get update",
          "apt-get install -y --no-install-recommends ca-certificates curl",
          "install -m 0755 -d /etc/apt/keyrings",
          "curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key -o /etc/apt/keyrings/jellyfin.asc",
          "chmod a+r /etc/apt/keyrings/jellyfin.asc",
          "echo 'deb [signed-by=/etc/apt/keyrings/jellyfin.asc] https://repo.jellyfin.org/ubuntu noble main' > /etc/apt/sources.list.d/jellyfin.list",
          "apt-get update",
          "apt-get install -y --no-install-recommends libjemalloc2 jellyfin jellyfin-server jellyfin-ffmpeg7",
          "ln -sf /usr/lib/jellyfin-ffmpeg/ffmpeg /usr/bin/ffmpeg",
          "ln -sf /usr/lib/jellyfin-ffmpeg/ffprobe /usr/bin/ffprobe",
          "systemctl enable --now jellyfin",
        ]
      }
    }
  }
)
