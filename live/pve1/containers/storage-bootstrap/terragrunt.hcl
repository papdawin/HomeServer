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

  # `terragrunt run --all --working-dir live/pve1/containers` does not include
  # units outside that folder by default. Ensure the external media storage
  # unit is applied first so storage-bootstrap can safely consume its outputs.
  before_hook "ensure_media_storage" {
    commands = ["apply"]
    execute = [
      "terragrunt",
      "apply",
      "-auto-approve",
      "--non-interactive",
      "--working-dir",
      "${get_repo_root()}/live/pve1/storage/media",
    ]
  }
}

locals {
  media_storage_id  = trimspace(get_env("MEDIA_STORAGE_ID", "media"))
  media_volume_size = trimspace(get_env("MEDIA_VOLUME_SIZE", "2T"))
  helper_start      = lower(trimspace(get_env("STORAGE_BOOTSTRAP_START", "true"))) == "true"
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = 124
  hostname   = "storage-bootstrap"
  ipv4_cidr  = "192.168.68.24/24"
  tags       = ["lxc", "nixos", "storage", "bootstrap"]
  start      = local.helper_start
  onboot     = false
  flake_file = "${get_repo_root()}/nix/storage-bootstrap/flake.nix"
  flake_attr = "storagebootstrap"
  mount_points = [
    {
      path   = "/media"
      volume = local.media_storage_id
      size   = local.media_volume_size
    },
    {
      path   = "/appdata-jellyfin"
      volume = local.media_storage_id
      size   = "20G"
    }
  ]
})
