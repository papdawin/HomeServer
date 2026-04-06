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
  media_volume_id            = trimspace(get_env("MEDIA_VOLUME_ID", "media:124/vm-124-disk-0.raw"))
  jellyfin_appdata_volume_id = trimspace(get_env("JELLYFIN_APPDATA_VOLUME_ID", "media:124/vm-124-disk-1.raw"))
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = 125
  hostname   = "jellyfin"
  ipv4_cidr  = "192.168.68.25/24"
  flake_file = "${get_repo_root()}/nix/jellyfin/flake.nix"
  flake_attr = "jellyfin"
  mount_points = [
    {
      path   = "/media"
      volume = local.media_volume_id
    },
    {
      path   = "/var/lib/jellyfin"
      volume = local.jellyfin_appdata_volume_id
    },
  ]
})
