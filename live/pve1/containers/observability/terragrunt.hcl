include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  observability_vmid = 142

  observability_appdata_volume_ref = "${include.lxc_common.locals.appdata_storage_path}/observability"
  observability_appdata_mount = {
    path   = "/var/lib/observability"
    volume = local.observability_appdata_volume_ref
  }
}

dependencies {
  paths = ["../../storage/appdata", "../storage-bootstrap"]
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = local.observability_vmid
  hostname   = "observability"
  ipv4_cidr  = "192.168.68.42/24"
  tags       = ["lxc", "nixos", "monitoring", "observability"]
  flake_file = "${get_repo_root()}/nix/observability/flake.nix"
  flake_attr = "observability"
  mount_points = [
    local.observability_appdata_mount,
  ]
})
