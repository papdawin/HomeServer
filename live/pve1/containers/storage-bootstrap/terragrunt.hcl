include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

dependency "media_storage" {
  config_path  = "../../storage/media"
  skip_outputs = true
}

dependency "appdata_storage" {
  config_path  = "../../storage/appdata"
  skip_outputs = true
}

dependencies {
  paths = ["../../storage/media", "../../storage/appdata"]
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

inputs = merge(include.lxc_common.inputs, {
  vmid      = 124
  hostname  = "storage-bootstrap"
  ipv4_cidr = "192.168.68.24/24"
  tags      = ["lxc", "nixos", "storage", "bootstrap"]
  # Keep this helper running so Terraform can always reach it over SSH
  # for flake_apply and directory reconciliation.
  start      = true
  onboot     = true
  flake_file = "${get_repo_root()}/nix/storage-bootstrap/flake.nix"
  flake_attr = "storagebootstrap"
  # This helper must run privileged so it can normalize host bind-mount
  # ownership/modes for unprivileged application containers.
  unprivileged          = false
  post_rebuild_commands = []
  mount_points = [
    {
      path   = "/media"
      volume = include.lxc_common.locals.media_storage_path
    },
    {
      path   = "/appdata"
      volume = include.lxc_common.locals.appdata_storage_path
    }
  ]
})
