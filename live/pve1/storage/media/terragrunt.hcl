include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  pve                = read_terragrunt_config(find_in_parent_folders("pve.hcl"))
  media_storage_id   = trimspace(get_env("MEDIA_STORAGE_ID", "media"))
  media_storage_path = trimspace(get_env("MEDIA_STORAGE_PATH", "/mnt/pve/HDD/media"))
}

terraform {
  source = "${get_repo_root()}/modules/storage-directory"
}

inputs = {
  storage_id    = local.media_storage_id
  path          = local.media_storage_path
  nodes         = [local.pve.inputs.target_node]
  content_types = ["rootdir"]
  shared        = false
  disable       = false
}
