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
  media_volume_id               = trimspace(get_env("MEDIA_VOLUME_ID", "media:124/vm-124-disk-0.raw"))
  qbittorrent_appdata_volume_id = trimspace(get_env("QBITTORRENT_APPDATA_VOLUME_ID", "media:124/vm-124-disk-2.raw"))
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = 126
  hostname   = "qbittorrent"
  ipv4_cidr  = "192.168.68.26/24"
  tags       = ["lxc", "nixos", "media", "downloads"]
  flake_file = "${get_repo_root()}/nix/qbittorrent/flake.nix"
  flake_attr = "qbittorrent"
  mount_points = [
    {
      path   = "/media"
      volume = local.media_volume_id
    },
    {
      path   = "/var/lib/qBittorrent"
      volume = local.qbittorrent_appdata_volume_id
    },
  ]
})
