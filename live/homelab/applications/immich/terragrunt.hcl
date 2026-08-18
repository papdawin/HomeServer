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
  source = "${get_repo_root()}/modules/applications/immich"
}

dependencies {
  paths = ["../immich-database", "../../identity/authentik-configuration", "../../platform/traefik"]
}

inputs = {
  chart_version         = local.environment.locals.immich_chart_version
  image_version         = local.environment.locals.immich_image_version
  domain                = local.environment.locals.domain
  machine_learning_node = local.environment.locals.control_plane_node
  oidc_client_id        = local.authentik_secrets.immich_oidc_client_id
  oidc_client_secret    = local.authentik_secrets.immich_oidc_client_secret
  secret_revision       = local.authentik_secret_revision
}
