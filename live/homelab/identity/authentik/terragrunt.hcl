include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
}

terraform {
  source = "${get_repo_root()}/modules/identity/authentik"
}

dependencies {
  paths = ["../authentik-database", "../../platform/traefik", "../../platform/certificate-configuration"]
}

inputs = {
  chart_version = local.environment.locals.authentik_chart_version
  domain        = local.environment.locals.domain
}
