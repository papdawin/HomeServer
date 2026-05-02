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
  vmid       = 126
  hostname   = "qbittorrent"
  ipv4_cidr  = "192.168.68.26/24"
  tags       = ["lxc", "nixos", "media", "downloads"]
  flake_file = "${get_repo_root()}/nix/qbittorrent/flake.nix"
  flake_attr = "qbittorrent"
  post_rebuild_commands = [
    <<-EOT
      printf '%s' '${base64encode(file("${get_repo_root()}/nix/qbittorrent/qbittorrent-bootstrap-user.sh"))}' | base64 -d >/tmp/qbittorrent-bootstrap-user.sh
      chmod 700 /tmp/qbittorrent-bootstrap-user.sh
      /tmp/qbittorrent-bootstrap-user.sh
      rm -f /tmp/qbittorrent-bootstrap-user.sh
      printf '%s' '${base64encode(file("${get_repo_root()}/nix/qbittorrent/qbittorrent-bootstrap-routing.sh"))}' | base64 -d >/tmp/qbittorrent-bootstrap-routing.sh
      chmod 700 /tmp/qbittorrent-bootstrap-routing.sh
      /tmp/qbittorrent-bootstrap-routing.sh
      rm -f /tmp/qbittorrent-bootstrap-routing.sh
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
