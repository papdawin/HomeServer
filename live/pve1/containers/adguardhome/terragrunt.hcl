include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = 139
  hostname   = "adguardhome"
  ipv4_cidr  = "192.168.68.39/24"
  tags       = ["lxc", "nixos", "dns", "adguard"]
  flake_file = "${get_repo_root()}/nix/adguardhome/flake.nix"
  flake_attr = "adguardhome"
})
