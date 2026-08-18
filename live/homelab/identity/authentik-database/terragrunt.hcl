include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment               = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  authentik_secret_file     = "${local.environment.locals.secrets_directory}/identity/authentik.sops.yaml"
  authentik_secrets         = yamldecode(sops_decrypt_file(local.authentik_secret_file)).secrets
  authentik_secret_revision = parseint(substr(filesha256(local.authentik_secret_file), 0, 8), 16)
}

terraform {
  source = "${get_repo_root()}/modules/shared/postgres-cluster"
}

dependencies {
  paths = ["../../platform/storage", "../../platform/cloudnative-pg"]
}

inputs = {
  namespace               = "authentik"
  cluster_name            = "authentik-postgres"
  database_name           = "authentik"
  database_owner          = "authentik"
  credentials_secret_name = "authentik-secrets"
  secret_data = {
    username                           = "authentik"
    password                           = local.authentik_secrets.database_password
    AUTHENTIK_SECRET_KEY               = local.authentik_secrets.secret_key
    AUTHENTIK_ERROR_REPORTING__ENABLED = "false"
    AUTHENTIK_POSTGRESQL__HOST         = "authentik-postgres-rw"
    AUTHENTIK_POSTGRESQL__PORT         = "5432"
    AUTHENTIK_POSTGRESQL__NAME         = "authentik"
    AUTHENTIK_POSTGRESQL__USER         = "authentik"
    AUTHENTIK_POSTGRESQL__PASSWORD     = local.authentik_secrets.database_password
    AUTHENTIK_BOOTSTRAP_EMAIL          = local.environment.locals.acme_email
    AUTHENTIK_BOOTSTRAP_PASSWORD       = local.authentik_secrets.bootstrap_password
    AUTHENTIK_BOOTSTRAP_TOKEN          = local.authentik_secrets.bootstrap_token
  }
  secret_revision          = local.authentik_secret_revision
  postgresql_image         = local.environment.locals.postgresql_image
  storage_size             = "20Gi"
  node_name                = local.environment.locals.worker_node
  backup_pvc_name          = "authentik-postgres-backups"
  backup_schedule          = "47 2 * * *"
  enable_immich_extensions = false
  resources = {
    requests = { cpu = "150m", memory = "384Mi" }
    limits   = { cpu = "1", memory = "1Gi" }
  }
}
