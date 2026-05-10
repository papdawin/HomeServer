include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  qbittorrent_vmid = 126

  qbittorrent_appdata_volume_ref = trimspace(get_env("QBITTORRENT_APPDATA_VOLUME", include.lxc_common.locals.appdata_storage_path))
  qbittorrent_appdata_mount = merge(
    {
      path   = "/appdata"
      volume = local.qbittorrent_appdata_volume_ref
    },
    startswith(local.qbittorrent_appdata_volume_ref, "/") ? {} : { size = "256G" },
  )
}

dependencies {
  paths = ["../../storage/appdata", "../storage-bootstrap"]
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = local.qbittorrent_vmid
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
    local.qbittorrent_appdata_mount,
    {
      path   = "/media"
      volume = include.lxc_common.locals.media_volume_fallback
    },
  ]
})
