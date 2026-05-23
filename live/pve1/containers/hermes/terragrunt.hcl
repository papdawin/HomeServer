include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  hermes_vmid = 127

  hermes_appdata_volume_ref = "${include.lxc_common.locals.appdata_storage_path}/hermes"
  hermes_appdata_mount = {
    path   = "/appdata"
    volume = local.hermes_appdata_volume_ref
  }
}

dependencies {
  paths = ["../../storage/appdata", "../storage-bootstrap"]
}

inputs = merge(include.lxc_common.inputs, {
  vmid        = local.hermes_vmid
  hostname    = "hermes"
  ipv4_cidr   = "192.168.68.27/24"
  tags        = ["lxc", "nixos", "ai", "hermes"]
  rootfs_size = "128G"
  flake_file  = "${get_repo_root()}/nix/hermes/flake.nix"
  flake_attr  = "hermes"
  mount_points = [
    local.hermes_appdata_mount,
  ]
})
