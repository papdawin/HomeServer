locals {
  pve                 = read_terragrunt_config(find_in_parent_folders("pve.hcl"))
  template_volid      = get_env("LXC_TEMPLATE", "local:vztmpl/nixos-proxmox-lxc.tar.xz")
  template_url        = get_env("NIXOS_LXC_TEMPLATE_URL", "https://hydra.nixos.org/job/nixos/release-25.11/nixos.proxmoxLXC.x86_64-linux/latest/download-by-type/file/system-tarball")
  ssh_agent_requested = lower(get_env("BOOTSTRAP_USE_SSH_AGENT", "true")) == "true"
  ssh_agent_available = trimspace(get_env("SSH_AUTH_SOCK", "")) != ""
  appdata_storage_id  = trimspace(get_env("APPDATA_STORAGE_ID", "appdata"))
  appdata_volume_size_gib = tonumber(trimspace(get_env("APPDATA_VOLUME_SIZE_GIB", "256")))
  appdata_volume_id_override = trimspace(get_env("APPDATA_VOLUME_ID", ""))
  appdata_mount_volume_ref = local.appdata_volume_id_override != "" ? local.appdata_volume_id_override : "${local.appdata_storage_id}:${local.appdata_volume_size_gib}"
  media_storage_id = trimspace(get_env("MEDIA_STORAGE_ID", "media"))
  media_volume_size_gib = tonumber(trimspace(get_env("MEDIA_VOLUME_SIZE_GIB", "2048")))
  media_volume_id_override = trimspace(get_env("MEDIA_VOLUME_ID", ""))
  media_bootstrap_vmid = tonumber(trimspace(get_env("MEDIA_BOOTSTRAP_VMID", "124")))
  media_mount_volume_ref = local.media_volume_id_override != "" ? local.media_volume_id_override : "${local.media_storage_id}:${local.media_volume_size_gib}"
  media_volume_fallback = local.media_volume_id_override != "" ? local.media_volume_id_override : "${local.media_storage_id}:${local.media_bootstrap_vmid}/vm-${local.media_bootstrap_vmid}-disk-0.raw"
}

terraform {
  source = "${get_repo_root()}/modules/lxc"

  before_hook "ensure_nixos_template" {
    commands = ["plan", "apply"]
    execute = [
      "bash",
      "${get_repo_root()}/scripts/ensure-nixos-template.sh",
      local.pve.inputs.target_node,
      local.template_volid,
      local.template_url,
    ]
  }
}

inputs = merge(local.pve.inputs, {
  ostemplate                 = local.template_volid
  ostype                     = "nixos"
  lxc_password               = get_env("LXC_PASSWORD", "")
  ssh_public_keys            = get_env("BOOTSTRAP_PUBLIC_KEY", "")
  common_sops_file           = "${get_repo_root()}/live/pve1/containers/common.sops.yaml"
  bootstrap_private_key_file = get_env("BOOTSTRAP_PRIVATE_KEY_FILE", "~/.ssh/id_ed25519")
  bootstrap_use_ssh_agent    = local.ssh_agent_requested && local.ssh_agent_available
  unprivileged               = true
  features_nesting           = true
  cores                      = 2
  memory                     = 4096
  swap                       = 512
  rootfs_size                = "32G"
})
