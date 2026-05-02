include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  pve                  = read_terragrunt_config(find_in_parent_folders("pve.hcl"))
  appdata_storage_id   = trimspace(get_env("APPDATA_STORAGE_ID", "appdata"))
  appdata_storage_path = trimspace(get_env("APPDATA_STORAGE_PATH", "/mnt/pve/HDD/appdata"))
}

terraform {
  source = "${get_repo_root()}/modules/storage-directory"
}

inputs = {
  storage_id    = local.appdata_storage_id
  path          = local.appdata_storage_path
  nodes         = [local.pve.inputs.target_node]
  content_types = ["rootdir"]
  shared        = false
  disable       = false
}
