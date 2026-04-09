include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

dependencies {
  paths = ["../storage-bootstrap", "../qbittorrent"]
}

locals {
  media_volume_id = trimspace(get_env("MEDIA_VOLUME_ID", "media:124/vm-124-disk-0.raw"))
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = 129
  hostname   = "radarr"
  ipv4_cidr  = "192.168.68.29/24"
  tags       = ["lxc", "nixos", "media", "radarr"]
  flake_file = "${get_repo_root()}/nix/radarr/flake.nix"
  flake_attr = "radarr"
  post_rebuild_commands = [
    <<-EOT
      printf '%s' '${base64encode(file("${get_repo_root()}/nix/radarr/radarr-bootstrap.sh"))}' | base64 -d >/tmp/radarr-bootstrap.sh
      chmod 700 /tmp/radarr-bootstrap.sh
      /tmp/radarr-bootstrap.sh
      rm -f /tmp/radarr-bootstrap.sh
    EOT
  ]
  mount_points = [
    {
      path   = "/media"
      volume = local.media_volume_id
    },
  ]
})
