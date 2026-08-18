include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
}

terraform {
  source = "${get_repo_root()}/modules/applications/hermes"
}

dependencies {
  paths = ["../../platform/foundation", "../../identity/authentik", "../../platform/traefik", "../../platform/storage"]
}

inputs = {
  namespace     = "hermes"
  domain        = local.environment.locals.domain
  authentik_url = "https://auth.${local.environment.locals.domain}"
}
