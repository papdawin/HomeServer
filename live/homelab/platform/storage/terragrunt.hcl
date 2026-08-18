include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment              = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  platform_secret_file     = "${local.environment.locals.secrets_directory}/platform.sops.yaml"
  platform_secrets         = yamldecode(sops_decrypt_file(local.platform_secret_file)).secrets
  platform_secret_revision = parseint(substr(filesha256(local.platform_secret_file), 0, 8), 16)
}

terraform {
  source = "${get_repo_root()}/modules/platform/storage"
}

dependencies {
  paths = ["../foundation"]
}

inputs = {
  worker_node           = local.environment.locals.worker_node
  control_plane_node    = local.environment.locals.control_plane_node
  worker_address        = local.environment.locals.worker_address
  control_plane_address = local.environment.locals.control_plane_ip
  truenas_address       = local.environment.locals.truenas_address
  truenas_pool          = local.environment.locals.truenas_pool
  truenas_csi_version   = local.environment.locals.truenas_csi_version
  truenas_csi_commit    = local.environment.locals.truenas_csi_commit
  truenas_csi_sha256    = local.environment.locals.truenas_csi_sha256
  local_path_version    = local.environment.locals.local_path_version
  truenas_api_key       = local.platform_secrets.truenas_api_key
  secret_revision       = local.platform_secret_revision

  # Keep false until the credential exposed in chat has been revoked and replaced.
  truenas_credential_rotated = true
}
