include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

inputs = merge(include.lxc_common.inputs, {
  vmid         = 133
  hostname     = "nomad"
  ipv4_cidr    = "192.168.68.33/24"
  tags         = ["lxc", "nixos", "travel", "nomad"]
  flake_file   = "${get_repo_root()}/nix/nomad/flake.nix"
  flake_attr   = "nomad"
  unprivileged = true
  cores        = 2
  memory       = 4096
  swap         = 1024
  rootfs_size  = "48G"
})
