include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment       = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  authentik_secrets = yamldecode(sops_decrypt_file("${local.environment.locals.secrets_directory}/identity/authentik.sops.yaml")).secrets
}

terraform {
  source = "${get_repo_root()}/modules/identity/authentik-configuration"
}

dependencies {
  paths = ["../authentik"]
}

inputs = {
  authentik_url      = "https://auth.${local.environment.locals.domain}"
  authentik_token    = local.authentik_secrets.bootstrap_token
  oidc_client_id     = local.authentik_secrets.immich_oidc_client_id
  oidc_client_secret = local.authentik_secrets.immich_oidc_client_secret
  immich_url         = "https://immich.${local.environment.locals.domain}"
  domain             = local.environment.locals.domain
}
