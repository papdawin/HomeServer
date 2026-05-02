include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
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

  # Nomad is the only container that owns the separate appdata storage.
  before_hook "ensure_appdata_storage" {
    commands = ["apply"]
    execute = [
      "terragrunt",
      "apply",
      "-auto-approve",
      "--non-interactive",
      "--working-dir",
      "${get_repo_root()}/live/pve1/storage/appdata",
    ]
  }
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
  mount_points = [
    {
      path   = "/appdata"
      volume = include.lxc_common.locals.appdata_storage_id
      size   = "${include.lxc_common.locals.appdata_volume_size_gib}G"
    },
  ]
})
