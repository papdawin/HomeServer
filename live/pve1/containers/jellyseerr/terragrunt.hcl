include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  jellyseerr_vmid = 132

  jellyseerr_appdata_volume_ref = trimspace(get_env("JELLYSEERR_APPDATA_VOLUME", include.lxc_common.locals.appdata_storage_path))
  jellyseerr_appdata_mount = merge(
    {
      path   = "/appdata"
      volume = local.jellyseerr_appdata_volume_ref
    },
    startswith(local.jellyseerr_appdata_volume_ref, "/") ? {} : { size = "256G" },
  )
}

dependencies {
  paths = [
    "../../storage/appdata",
    "../storage-bootstrap",
    "../jellyfin",
    "../radarr",
    "../sonarr",
  ]
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = local.jellyseerr_vmid
  hostname   = "jellyseerr"
  ipv4_cidr  = "192.168.68.32/24"
  tags       = ["lxc", "nixos", "media", "jellyseerr"]
  flake_file = "${get_repo_root()}/nix/jellyseerr/flake.nix"
  flake_attr = "jellyseerr"
  post_rebuild_commands = [
    <<-EOT
      set -euo pipefail
      printf '%s' '${base64encode(file("${get_repo_root()}/nix/jellyseerr/jellyseerr-bootstrap.sh"))}' | base64 -d >/tmp/jellyseerr-bootstrap.sh
      chmod 700 /tmp/jellyseerr-bootstrap.sh
      /tmp/jellyseerr-bootstrap.sh
      rm -f /tmp/jellyseerr-bootstrap.sh
    EOT
  ]
  post_rebuild_command_timeout_seconds = 1200
  post_rebuild_continue_on_error       = false
  mount_points = [
    local.jellyseerr_appdata_mount,
    {
      path   = "/media"
      volume = include.lxc_common.locals.media_volume_fallback
    },
  ]
})
