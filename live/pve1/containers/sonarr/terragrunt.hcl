include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  sonarr_vmid = 130

  sonarr_appdata_volume_ref = "${include.lxc_common.locals.appdata_storage_path}/sonarr"
  sonarr_appdata_mount = {
    path   = "/appdata"
    volume = local.sonarr_appdata_volume_ref
  }
}

dependencies {
  paths = ["../../storage/appdata", "../storage-bootstrap"]
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = local.sonarr_vmid
  hostname   = "sonarr"
  ipv4_cidr  = "192.168.68.30/24"
  tags       = ["lxc", "nixos", "media", "sonarr"]
  flake_file = "${get_repo_root()}/nix/sonarr/flake.nix"
  flake_attr = "sonarr"
  post_rebuild_commands = [
    <<-EOT
      systemctl restart sonarr-credentials.service
      systemctl restart sonarr-bootstrap-user.service
      printf '%s' '${base64encode(file("${get_repo_root()}/nix/sonarr/sonarr-bootstrap.sh"))}' | base64 -d >/tmp/sonarr-bootstrap.sh
      chmod 700 /tmp/sonarr-bootstrap.sh
      /tmp/sonarr-bootstrap.sh
      rm -f /tmp/sonarr-bootstrap.sh
    EOT
  ]
  mount_points = [
    local.sonarr_appdata_mount,
    {
      path   = "/media"
      volume = include.lxc_common.locals.media_volume_fallback
    },
  ]
})
