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
  vmid       = 130
  hostname   = "sonarr"
  ipv4_cidr  = "192.168.68.30/24"
  tags       = ["lxc", "nixos", "media", "sonarr"]
  flake_file = "${get_repo_root()}/nix/sonarr/flake.nix"
  flake_attr = "sonarr"
  post_rebuild_commands = [
    <<-EOT
      printf '%s' '${base64encode(file("${get_repo_root()}/nix/sonarr/sonarr-bootstrap.sh"))}' | base64 -d >/tmp/sonarr-bootstrap.sh
      chmod 700 /tmp/sonarr-bootstrap.sh
      /tmp/sonarr-bootstrap.sh
      rm -f /tmp/sonarr-bootstrap.sh
    EOT
  ]
  mount_points = [
    {
      path   = "/media"
      volume = local.media_volume_id
    },
  ]
})
