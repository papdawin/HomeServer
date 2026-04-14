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
        path_in_datastore = "${trimspace(get_env("MEDIA_STORAGE_ID", "media"))}:124/vm-124-disk-0.raw"
        volume            = "${trimspace(get_env("MEDIA_STORAGE_ID", "media"))}:124/vm-124-disk-0.raw"
      }
    ]
  }
}

locals {
  media_storage_id      = trimspace(get_env("MEDIA_STORAGE_ID", "media"))
  media_volume_fallback = "${local.media_storage_id}:124/vm-124-disk-0.raw"
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
      systemctl --no-pager --full status jellyfin-credentials.service jellyfin-bootstrap.service || true
      journalctl -u jellyfin-credentials.service -u jellyfin-bootstrap.service -n 200 --no-pager || true
    EOT
  ]
  mount_points = [
    {
      path = "/media"
      volume = try(
        [for mount_point in dependency.storage_bootstrap.outputs.mount_points : try(mount_point.path_in_datastore, mount_point.volume) if mount_point.path == "/media"][0],
        local.media_volume_fallback
      )
    },
  ]
})
