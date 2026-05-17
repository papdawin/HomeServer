include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  prowlarr_vmid = 131

  prowlarr_appdata_volume_ref = "${include.lxc_common.locals.appdata_storage_path}/prowlarr"
  prowlarr_appdata_mount = {
    path   = "/appdata"
    volume = local.prowlarr_appdata_volume_ref
  }
}

dependencies {
  paths = [
    "../../storage/appdata",
    "../storage-bootstrap",
    "../radarr",
    "../sonarr",
  ]
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = local.prowlarr_vmid
  hostname   = "prowlarr"
  ipv4_cidr  = "192.168.68.31/24"
  tags       = ["lxc", "nixos", "media", "prowlarr"]
  flake_file = "${get_repo_root()}/nix/prowlarr/flake.nix"
  flake_attr = "prowlarr"
  post_rebuild_commands = [
    <<-EOT
      set -euo pipefail
      systemctl restart prowlarr-credentials.service
      systemctl restart prowlarr-bootstrap-user.service
      printf '%s' '${base64encode(file("${get_repo_root()}/nix/prowlarr/prowlarr-bootstrap.sh"))}' | base64 -d >/tmp/prowlarr-bootstrap.sh
      chmod 700 /tmp/prowlarr-bootstrap.sh
      /tmp/prowlarr-bootstrap.sh
      rm -f /tmp/prowlarr-bootstrap.sh
    EOT
  ]
  post_rebuild_command_timeout_seconds = 1200
  post_rebuild_continue_on_error       = false
  mount_points = [
    local.prowlarr_appdata_mount,
    {
      path   = "/media"
      volume = include.lxc_common.locals.media_volume_fallback
    },
  ]
})
