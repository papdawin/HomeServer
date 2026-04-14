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

inputs = merge(include.lxc_common.inputs, {
  vmid        = 127
  hostname    = "openclaw"
  ipv4_cidr   = "192.168.68.27/24"
  tags        = ["lxc", "nixos", "ai", "gateway"]
  rootfs_size = "128G"
  flake_file  = "${get_repo_root()}/nix/openclaw/flake.nix"
  flake_attr  = "openclaw"
})
