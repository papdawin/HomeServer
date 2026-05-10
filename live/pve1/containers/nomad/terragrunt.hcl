include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  nomad_vmid = 133

  nomad_appdata_volume_ref = trimspace(get_env("NOMAD_APPDATA_VOLUME", include.lxc_common.locals.appdata_storage_path))
  nomad_appdata_mount = merge(
    {
      path   = "/appdata"
      volume = local.nomad_appdata_volume_ref
    },
    startswith(local.nomad_appdata_volume_ref, "/") ? {} : { size = "32G" },
  )
}

terraform {
  source = "${get_repo_root()}/modules/lxc"

  before_hook "ensure_nixos_template" {
    commands = ["plan", "apply"]
    execute = [
      "bash",
      "${get_repo_root()}/scripts/ensure-nixos-template.sh",
      include.lxc_common.locals.pve.inputs.target_node,
      include.lxc_common.locals.template_volid,
      include.lxc_common.locals.template_url,
    ]
  }

}

dependencies {
  paths = ["../../storage/appdata", "../storage-bootstrap"]
}

inputs = merge(include.lxc_common.inputs, {
  vmid         = local.nomad_vmid
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
  mount_points = [
    local.nomad_appdata_mount,
  ]
})
