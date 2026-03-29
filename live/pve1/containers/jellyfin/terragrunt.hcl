include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  pve                 = read_terragrunt_config(find_in_parent_folders("pve.hcl"))
  template_volid      = get_env("LXC_TEMPLATE", "local:vztmpl/nixos-proxmox-lxc.tar.xz")
  template_url        = get_env("NIXOS_LXC_TEMPLATE_URL", "https://hydra.nixos.org/job/nixos/release-25.11/nixos.proxmoxLXC.x86_64-linux/latest/download-by-type/file/system-tarball")
  ssh_agent_requested = lower(get_env("BOOTSTRAP_USE_SSH_AGENT", "true")) == "true"
  ssh_agent_available = trimspace(get_env("SSH_AUTH_SOCK", "")) != ""
}

terraform {
  source = "../../../../modules/lxc"

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
  vmid                    = 125
  hostname                = "jellyfin"
  ostemplate              = local.template_volid
  ostype                  = "nixos"
  lxc_password            = get_env("LXC_PASSWORD", "")
  ssh_public_keys         = get_env("BOOTSTRAP_PUBLIC_KEY", "")
  bootstrap_use_ssh_agent = local.ssh_agent_requested && local.ssh_agent_available
  unprivileged            = true
  features_nesting        = true
  cores                   = 2
  memory                  = 4096
  swap                    = 512
  rootfs_size             = "32G"
  ipv4_cidr               = "192.168.68.25/24"
  flake_file              = "${get_repo_root()}/nix/jellyfin/flake.nix"
  flake_attr              = "jellyfin"
})
