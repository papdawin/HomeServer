include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

dependencies {
  paths = ["../../storage/media"]
}

dependency "media_storage" {
  config_path = "../../storage/media"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    storage_id = "media"
  }
}

locals {
  media_volume_size = trimspace(get_env("MEDIA_VOLUME_SIZE", "2T"))
  helper_start      = lower(trimspace(get_env("STORAGE_BOOTSTRAP_START", "true"))) == "true"
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = 124
  hostname   = "storage-bootstrap"
  ipv4_cidr  = "192.168.68.24/24"
  start      = local.helper_start
  onboot     = false
  flake_file = "${get_repo_root()}/nix/storage-bootstrap/flake.nix"
  flake_attr = "storagebootstrap"
  mount_points = [
    {
      path   = "/media"
      volume = dependency.media_storage.outputs.storage_id
      size   = local.media_volume_size
    }
  ]
})
