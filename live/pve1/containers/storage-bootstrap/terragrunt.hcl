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

dependencies {
  paths = ["../../storage/media"]
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
  vmid       = 124
  hostname   = "storage-bootstrap"
  ipv4_cidr  = "192.168.68.24/24"
  tags       = ["lxc", "nixos", "storage", "bootstrap"]
  start      = true
  onboot     = false
  flake_file = "${get_repo_root()}/nix/storage-bootstrap/flake.nix"
  flake_attr = "storagebootstrap"
  post_rebuild_commands = [
    "shutdown -P +5 'storage bootstrap apply completed'",
  ]
  mount_points = [
    {
      path   = "/media"
      volume = include.lxc_common.locals.media_mount_volume_ref
    }
  ]
})
