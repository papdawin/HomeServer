include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  immich_vmid = 128

  immich_appdata_volume_ref = "${include.lxc_common.locals.appdata_storage_path}/immich"
  immich_appdata_mount = {
    path   = "/appdata"
    volume = local.immich_appdata_volume_ref
  }
}

dependencies {
  paths = ["../../storage/appdata", "../storage-bootstrap"]
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = local.immich_vmid
  hostname   = "immich"
  ipv4_cidr  = "192.168.68.28/24"
  tags       = ["lxc", "nixos", "media", "photos"]
  flake_file = "${get_repo_root()}/nix/immich/flake.nix"
  flake_attr = "immich"
  mount_points = [
    local.immich_appdata_mount,
  ]
})
