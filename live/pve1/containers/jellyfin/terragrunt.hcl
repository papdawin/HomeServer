include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  jellyfin_vmid = 125

  jellyfin_appdata_volume_ref = trimspace(get_env("JELLYFIN_APPDATA_VOLUME", include.lxc_common.locals.appdata_storage_path))
  jellyfin_appdata_mount = merge(
    {
      path   = "/appdata"
      volume = local.jellyfin_appdata_volume_ref
    },
    startswith(local.jellyfin_appdata_volume_ref, "/") ? {} : { size = "256G" },
  )
}

dependencies {
  paths = ["../../storage/appdata", "../storage-bootstrap"]
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = local.jellyfin_vmid
  hostname   = "jellyfin"
  ipv4_cidr  = "192.168.68.25/24"
  tags       = ["lxc", "nixos", "media", "streaming"]
  flake_file = "${get_repo_root()}/nix/jellyfin/flake.nix"
  flake_attr = "jellyfin"
  post_rebuild_commands = [
    <<-EOT
      systemctl restart jellyfin-credentials.service
      systemctl restart jellyfin-bootstrap.service
      systemctl restart jellyfin-bootstrap-libraries.service
      systemctl --no-pager --full status jellyfin-credentials.service jellyfin-bootstrap.service jellyfin-bootstrap-libraries.service || true
      journalctl -u jellyfin-credentials.service -u jellyfin-bootstrap.service -u jellyfin-bootstrap-libraries.service -n 200 --no-pager || true
    EOT
  ]
  mount_points = [
    local.jellyfin_appdata_mount,
    {
      path   = "/media"
      volume = include.lxc_common.locals.media_volume_fallback
    },
  ]
})
