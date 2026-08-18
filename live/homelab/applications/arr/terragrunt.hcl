include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
}

terraform {
  source = "${get_repo_root()}/modules/applications/arr"
}

dependencies {
  paths = ["../../platform/storage", "../../platform/traefik", "../../identity/authentik-configuration"]
}

inputs = {
  namespace     = "arr"
  domain        = local.environment.locals.domain
  authentik_url = "https://auth.${local.environment.locals.domain}"
}
