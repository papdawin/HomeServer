include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  nextcloud_vmid = 134

  nextcloud_appdata_volume_ref = trimspace(get_env("NEXTCLOUD_APPDATA_VOLUME", include.lxc_common.locals.appdata_storage_path))
  nextcloud_appdata_mount = merge(
    {
      path   = "/appdata"
      volume = local.nextcloud_appdata_volume_ref
    },
    startswith(local.nextcloud_appdata_volume_ref, "/") ? {} : { size = "256G" },
  )
}

dependencies {
  paths = ["../../storage/appdata", "../storage-bootstrap"]
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = local.nextcloud_vmid
  hostname   = "nextcloud"
  ipv4_cidr  = "192.168.68.34/24"
  tags       = ["lxc", "nixos", "media", "nextcloud"]
  flake_file = "${get_repo_root()}/nix/nextcloud/flake.nix"
  flake_attr = "nextcloud"
  post_rebuild_commands = [
    <<-EOT
      set -euo pipefail
      systemctl restart nextcloud-credentials.service
      systemctl reset-failed nextcloud-bootstrap-user.service || true
      systemctl start --no-block nextcloud-bootstrap-user.service || true
      systemctl --no-pager --full status nextcloud-credentials.service nextcloud-bootstrap-user.service || true
      journalctl -u nextcloud-credentials.service -u nextcloud-bootstrap-user.service -n 200 --no-pager || true
    EOT
  ]
  post_rebuild_command_timeout_seconds = 180
  post_rebuild_continue_on_error       = false
  mount_points = [
    local.nextcloud_appdata_mount,
    {
      path   = "/media"
      volume = include.lxc_common.locals.media_volume_fallback
    },
  ]
})
