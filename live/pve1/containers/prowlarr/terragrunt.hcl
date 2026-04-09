include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

dependencies {
  paths = ["../storage-bootstrap", "../radarr", "../sonarr"]
}

locals {
  media_volume_id = trimspace(get_env("MEDIA_VOLUME_ID", "media:124/vm-124-disk-0.raw"))
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = 131
  hostname   = "prowlarr"
  ipv4_cidr  = "192.168.68.31/24"
  tags       = ["lxc", "nixos", "media", "prowlarr"]
  flake_file = "${get_repo_root()}/nix/prowlarr/flake.nix"
  flake_attr = "prowlarr"
  post_rebuild_commands = [
    <<-EOT
      printf '%s' '${base64encode(file("${get_repo_root()}/nix/prowlarr/prowlarr-bootstrap.sh"))}' | base64 -d >/tmp/prowlarr-bootstrap.sh
      chmod 700 /tmp/prowlarr-bootstrap.sh
      /tmp/prowlarr-bootstrap.sh
      rm -f /tmp/prowlarr-bootstrap.sh
    EOT
  ]
  mount_points = [
    {
      path   = "/media"
      volume = local.media_volume_id
    },
  ]
})
