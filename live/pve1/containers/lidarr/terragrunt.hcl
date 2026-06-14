include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  lidarr_vmid = 140

  lidarr_appdata_mount = {
    path   = "/appdata"
    volume = include.lxc_common.locals.appdata_mount_volume_ref
  }
}

dependencies {
  paths = ["../../storage/appdata", "../storage-bootstrap"]
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = local.lidarr_vmid
  hostname   = "lidarr"
  ipv4_cidr  = "192.168.68.40/24"
  tags       = ["lxc", "nixos", "media", "lidarr"]
  flake_file = "${get_repo_root()}/nix/lidarr/flake.nix"
  flake_attr = "lidarr"
  post_rebuild_commands = [
    <<-EOT
      systemctl restart lidarr-credentials.service
      systemctl restart lidarr-bootstrap-user.service
      printf '%s' '${base64encode(file("${get_repo_root()}/nix/lidarr/lidarr-bootstrap.sh"))}' | base64 -d >/tmp/lidarr-bootstrap.sh
      chmod 700 /tmp/lidarr-bootstrap.sh
      /tmp/lidarr-bootstrap.sh
      rm -f /tmp/lidarr-bootstrap.sh
    EOT
  ]
  mount_points = [
    local.lidarr_appdata_mount,
    {
      path   = "/media"
      volume = include.lxc_common.locals.media_volume_fallback
    },
  ]
})
