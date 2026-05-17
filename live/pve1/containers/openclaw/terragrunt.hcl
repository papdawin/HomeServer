include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  openclaw_vmid = 127

  openclaw_appdata_volume_ref = "${include.lxc_common.locals.appdata_storage_path}/openclaw"
  openclaw_appdata_mount = {
    path   = "/appdata"
    volume = local.openclaw_appdata_volume_ref
  }
}

dependencies {
  paths = ["../../storage/appdata", "../storage-bootstrap"]
}

inputs = merge(include.lxc_common.inputs, {
  vmid        = local.openclaw_vmid
  hostname    = "openclaw"
  ipv4_cidr   = "192.168.68.27/24"
  tags        = ["lxc", "nixos", "ai", "gateway"]
  rootfs_size = "128G"
  flake_file  = "${get_repo_root()}/nix/openclaw/flake.nix"
  flake_attr  = "openclaw"
  mount_points = [
    local.openclaw_appdata_mount,
  ]
})
