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
  vmid       = 130
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
    {
      path = "/media"
      volume = try(
        [for mount_point in dependency.storage_bootstrap.outputs.mount_points : try(mount_point.path_in_datastore, mount_point.volume) if mount_point.path == "/media"][0],
        include.lxc_common.locals.media_volume_fallback
      )
    },
  ]
})
