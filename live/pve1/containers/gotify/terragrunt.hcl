include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  gotify_vmid = 137

  gotify_appdata_volume_ref = "${include.lxc_common.locals.appdata_storage_path}/gotify"
  gotify_appdata_mount = {
    path   = "/appdata"
    volume = local.gotify_appdata_volume_ref
  }
}

dependencies {
  paths = ["../../storage/appdata", "../storage-bootstrap"]
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = local.gotify_vmid
  hostname   = "gotify"
  ipv4_cidr  = "192.168.68.37/24"
  tags       = ["lxc", "nixos", "ops", "gotify"]
  flake_file = "${get_repo_root()}/nix/gotify/flake.nix"
  flake_attr = "gotify"
  mount_points = [
    local.gotify_appdata_mount,
  ]
})
