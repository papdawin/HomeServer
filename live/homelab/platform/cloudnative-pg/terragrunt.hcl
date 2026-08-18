include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
}

terraform {
  source = "${get_repo_root()}/modules/platform/cloudnative-pg"
}

dependencies {
  paths = ["../foundation"]
}

inputs = {
  chart_version = local.environment.locals.cnpg_chart_version
}
