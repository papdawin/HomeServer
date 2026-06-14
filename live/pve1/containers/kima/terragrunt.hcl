include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  kima_vmid = 141

  kima_appdata_mount = {
    path   = "/appdata"
    volume = include.lxc_common.locals.appdata_mount_volume_ref
  }
}

dependencies {
  paths = [
    "../../storage/appdata",
    "../storage-bootstrap",
    "../lidarr",
  ]
}

inputs = merge(include.lxc_common.inputs, {
  vmid        = local.kima_vmid
  hostname    = "kima"
  ipv4_cidr   = "192.168.68.41/24"
  tags        = ["lxc", "nixos", "media", "kima"]
  cores       = 4
  memory      = 8192
  swap        = 2048
  rootfs_size = "96G"
  flake_file  = "${get_repo_root()}/nix/kima/flake.nix"
  flake_attr  = "kima"
  mount_points = [
    local.kima_appdata_mount,
    {
      path   = "/media"
      volume = include.lxc_common.locals.media_volume_fallback
    },
  ]
})
