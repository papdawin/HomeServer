include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  mealie_vmid = 136

  mealie_appdata_volume_ref = "${include.lxc_common.locals.appdata_storage_path}/mealie"
  mealie_appdata_mount = {
    path   = "/appdata"
    volume = local.mealie_appdata_volume_ref
  }
}

dependencies {
  paths = ["../../storage/appdata", "../storage-bootstrap"]
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = local.mealie_vmid
  hostname   = "mealie"
  ipv4_cidr  = "192.168.68.36/24"
  tags       = ["lxc", "nixos", "home", "mealie"]
  flake_file = "${get_repo_root()}/nix/mealie/flake.nix"
  flake_attr = "mealie"
  mount_points = [
    local.mealie_appdata_mount,
  ]
})
