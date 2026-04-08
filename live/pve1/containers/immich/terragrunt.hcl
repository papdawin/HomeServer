include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = 128
  hostname   = "immich"
  ipv4_cidr  = "192.168.68.28/24"
  tags       = ["lxc", "nixos", "media", "photos"]
  flake_file = "${get_repo_root()}/nix/immich/flake.nix"
  flake_attr = "immich"
})
