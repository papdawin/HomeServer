include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  pve                  = read_terragrunt_config(find_in_parent_folders("pve.hcl"))
  appdata_storage_id   = trimspace(get_env("APPDATA_STORAGE_ID", "appdata"))
  appdata_storage_path = trimspace(get_env("APPDATA_STORAGE_PATH", "/mnt/pve/HDD/appdata"))
  # Safety default: false. Set APPDATA_ALLOW_DESTROY=true (or ALLOW_STORAGE_DESTROY=true)
  # only when you intentionally want to delete this Proxmox storage definition.
  appdata_allow_destroy = lower(trimspace(get_env("APPDATA_ALLOW_DESTROY", get_env("ALLOW_STORAGE_DESTROY", "false")))) == "true"
}

terraform {
  source = local.appdata_allow_destroy ? "${get_repo_root()}/modules/storage-directory-destroyable" : "${get_repo_root()}/modules/storage-directory"
}

inputs = {
  storage_id    = local.appdata_storage_id
  path          = local.appdata_storage_path
  nodes         = [local.pve.inputs.target_node]
  content_types = ["rootdir"]
  shared        = false
  disable       = false
}
