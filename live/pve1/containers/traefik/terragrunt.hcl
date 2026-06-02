include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  traefik_vmid = 138

  traefik_appdata_volume_ref = "${include.lxc_common.locals.appdata_storage_path}/traefik"
  traefik_appdata_mount = {
    path   = "/var/lib/traefik"
    volume = local.traefik_appdata_volume_ref
  }
}

dependencies {
  paths = ["../../storage/appdata", "../storage-bootstrap"]
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = local.traefik_vmid
  hostname   = "traefik"
  ipv4_cidr  = "192.168.68.38/24"
  tags       = ["lxc", "nixos", "proxy", "https"]
  flake_file = "${get_repo_root()}/nix/traefik/flake.nix"
  flake_attr = "traefik"
  mount_points = [
    local.traefik_appdata_mount,
  ]
})
