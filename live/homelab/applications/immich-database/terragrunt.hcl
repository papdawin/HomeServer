include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment            = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  immich_secret_file     = "${local.environment.locals.secrets_directory}/applications/immich.sops.yaml"
  immich_secrets         = yamldecode(sops_decrypt_file(local.immich_secret_file)).secrets
  immich_secret_revision = parseint(substr(filesha256(local.immich_secret_file), 0, 8), 16)
}

terraform {
  source = "${get_repo_root()}/modules/shared/postgres-cluster"
}

dependencies {
  paths = ["../../platform/storage", "../../platform/cloudnative-pg"]
}

inputs = {
  namespace               = "immich"
  cluster_name            = "immich-postgres"
  database_name           = "immich"
  database_owner          = "immich"
  credentials_secret_name = "immich-postgres-credentials"
  secret_data = {
    username = "immich"
    password = local.immich_secrets.database_password
  }
  secret_revision          = local.immich_secret_revision
  postgresql_image         = local.environment.locals.postgresql_image
  vectorchord_image        = local.environment.locals.vectorchord_image
  storage_size             = "50Gi"
  node_name                = local.environment.locals.control_plane_node
  backup_pvc_name          = "immich-postgres-backups"
  backup_schedule          = "17 2 * * *"
  enable_immich_extensions = true
  resources = {
    requests = { cpu = "250m", memory = "512Mi" }
    limits   = { cpu = "2", memory = "2Gi" }
  }
}
