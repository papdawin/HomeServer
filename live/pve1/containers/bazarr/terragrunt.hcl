include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  bazarr_vmid = 135

  bazarr_appdata_volume_ref = "${include.lxc_common.locals.appdata_storage_path}/bazarr"
  bazarr_appdata_mount = {
    path   = "/appdata"
    volume = local.bazarr_appdata_volume_ref
  }
}

dependencies {
  paths = [
    "../../storage/appdata",
    "../storage-bootstrap",
  ]
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = local.bazarr_vmid
  hostname   = "bazarr"
  ipv4_cidr  = "192.168.68.35/24"
  tags       = ["lxc", "nixos", "media", "bazarr"]
  flake_file = "${get_repo_root()}/nix/bazarr/flake.nix"
  flake_attr = "bazarr"
  post_rebuild_commands = [
    <<-EOT
      set -euo pipefail
      systemctl restart bazarr-credentials.service
      systemctl restart bazarr-bootstrap-user.service
    EOT
  ]
  post_rebuild_command_timeout_seconds = 1200
  post_rebuild_continue_on_error       = false
  mount_points = [
    local.bazarr_appdata_mount,
    {
      path   = "/media"
      volume = include.lxc_common.locals.media_volume_fallback
    },
  ]
})
