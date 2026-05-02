include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

dependencies {
  paths = ["../storage-bootstrap"]
}

dependency "storage_bootstrap" {
  config_path = "../storage-bootstrap"

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "apply"]
  mock_outputs = {
    mount_points = [
      {
        path              = "/media"
        path_in_datastore = "${include.lxc_common.locals.media_volume_fallback}"
        volume            = "${include.lxc_common.locals.media_volume_fallback}"
      }
    ]
  }
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = 125
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
    {
      path = "/media"
      volume = try(
        [for mount_point in dependency.storage_bootstrap.outputs.mount_points : try(mount_point.path_in_datastore, mount_point.volume) if mount_point.path == "/media"][0],
        include.lxc_common.locals.media_volume_fallback
      )
    },
  ]
})
