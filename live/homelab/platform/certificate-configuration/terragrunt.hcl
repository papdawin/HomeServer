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
  source = "${get_repo_root()}/modules/platform/certificate-configuration"
}

dependencies {
  paths = ["../cert-manager", "../traefik"]
}

inputs = {
  cloudflare_api_token    = local.platform_secrets.cloudflare_api_token
  secret_revision         = local.platform_secret_revision
  domain                  = local.environment.locals.domain
  dns_zone                = local.environment.locals.dns_zone
  acme_email              = local.environment.locals.acme_email
  certificate_issuer_name = "letsencrypt-production"
}
