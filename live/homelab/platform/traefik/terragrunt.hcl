include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
}

terraform {
  source = "${get_repo_root()}/modules/platform/traefik"
}

dependencies {
  paths = ["../foundation"]
}

inputs = {
  chart_version = local.environment.locals.traefik_chart_version
  domain        = local.environment.locals.domain
}
