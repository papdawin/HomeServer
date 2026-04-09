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

locals {
  media_volume_id            = trimspace(get_env("MEDIA_VOLUME_ID", "media:124/vm-124-disk-0.raw"))
  jellyfin_appdata_volume_id = trimspace(get_env("JELLYFIN_APPDATA_VOLUME_ID", "media:124/vm-124-disk-1.raw"))
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
      printf '%s' '${base64encode(file("${get_repo_root()}/nix/jellyfin/jellyfin-bootstrap-user.sh"))}' | base64 -d >/tmp/jellyfin-bootstrap-user.sh
      chmod 700 /tmp/jellyfin-bootstrap-user.sh
      /tmp/jellyfin-bootstrap-user.sh
      rm -f /tmp/jellyfin-bootstrap-user.sh
      printf '%s' '${base64encode(file("${get_repo_root()}/nix/jellyfin/jellyfin-bootstrap-libraries.sh"))}' | base64 -d >/tmp/jellyfin-bootstrap-libraries.sh
      chmod 700 /tmp/jellyfin-bootstrap-libraries.sh
      /tmp/jellyfin-bootstrap-libraries.sh
      rm -f /tmp/jellyfin-bootstrap-libraries.sh
    EOT
  ]
  mount_points = [
    {
      path   = "/media"
      volume = local.media_volume_id
    },
    {
      path   = "/var/lib/jellyfin"
      volume = local.jellyfin_appdata_volume_id
    },
  ]
})
