include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "lxc_common" {
  path   = "${get_terragrunt_dir()}/../common.hcl"
  expose = true
}

locals {
  radarr_vmid = 129

  radarr_appdata_volume_ref = trimspace(get_env("RADARR_APPDATA_VOLUME", include.lxc_common.locals.appdata_storage_path))
  radarr_appdata_mount = merge(
    {
      path   = "/appdata"
      volume = local.radarr_appdata_volume_ref
    },
    startswith(local.radarr_appdata_volume_ref, "/") ? {} : { size = "256G" },
  )
}

dependencies {
  paths = ["../../storage/appdata", "../storage-bootstrap"]
}

inputs = merge(include.lxc_common.inputs, {
  vmid       = local.radarr_vmid
  hostname   = "radarr"
  ipv4_cidr  = "192.168.68.29/24"
  tags       = ["lxc", "nixos", "media", "radarr"]
  flake_file = "${get_repo_root()}/nix/radarr/flake.nix"
  flake_attr = "radarr"
  post_rebuild_commands = [
    <<-EOT
      systemctl restart radarr-credentials.service
      systemctl restart radarr-bootstrap-user.service
      printf '%s' '${base64encode(file("${get_repo_root()}/nix/radarr/radarr-bootstrap.sh"))}' | base64 -d >/tmp/radarr-bootstrap.sh
      chmod 700 /tmp/radarr-bootstrap.sh
      /tmp/radarr-bootstrap.sh
      rm -f /tmp/radarr-bootstrap.sh
    EOT
  ]
  mount_points = [
    local.radarr_appdata_mount,
    {
      path   = "/media"
      volume = include.lxc_common.locals.media_volume_fallback
    },
  ]
})
