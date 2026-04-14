include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

dependencies {
  paths = ["../storage-bootstrap", "../jellyfin", "../radarr", "../sonarr", "../prowlarr"]
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
  vmid       = 132
  hostname   = "jellyseerr"
  ipv4_cidr  = "192.168.68.32/24"
  tags       = ["lxc", "nixos", "media", "jellyseerr"]
  flake_file = "${get_repo_root()}/nix/jellyseerr/flake.nix"
  flake_attr = "jellyseerr"
  post_rebuild_commands = [
    <<-EOT
      printf '%s' '${base64encode(file("${get_repo_root()}/nix/jellyseerr/jellyseerr-bootstrap.sh"))}' | base64 -d >/tmp/jellyseerr-bootstrap.sh
      chmod 700 /tmp/jellyseerr-bootstrap.sh
      /tmp/jellyseerr-bootstrap.sh
      rm -f /tmp/jellyseerr-bootstrap.sh
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
