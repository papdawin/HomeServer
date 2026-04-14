include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

dependencies {
  paths = ["../storage-bootstrap"]
}

locals {
  media_volume_id = trimspace(get_env("MEDIA_VOLUME_ID", "media:124/vm-124-disk-0.raw"))
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = 125
  hostname   = "jellyfin"
  ipv4_cidr  = "192.168.68.25/24"
  tags       = ["lxc", "nixos", "media", "streaming"]
  flake_file = "${get_repo_root()}/nix/jellyfin/flake.nix"
  flake_attr = "jellyfin"
  post_rebuild_commands = [
    <<-EOT
      systemctl restart jellyfin-credentials.service
      systemctl restart jellyfin-bootstrap.service
      systemctl --no-pager --full status jellyfin-credentials.service jellyfin-bootstrap.service || true
      journalctl -u jellyfin-credentials.service -u jellyfin-bootstrap.service -n 200 --no-pager || true
    EOT
  ]
  mount_points = [
    {
      path   = "/media"
      volume = local.media_volume_id
    },
  ]
})
