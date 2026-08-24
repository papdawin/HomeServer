include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
}

terraform {
  source = "${get_repo_root()}/modules/applications/homeassistant"
}

dependencies {
  paths = ["../../platform/foundation", "../../identity/authentik", "../../platform/traefik", "../../platform/storage"]
}

inputs = {
  namespace     = "homeassistant"
  domain        = local.environment.locals.domain
  authentik_url = "https://auth.${local.environment.locals.domain}"
}
