include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
}

terraform {
  source = "${get_repo_root()}/modules/platform/foundation"
}

inputs = {
  gateway_api_version = local.environment.locals.gateway_api_version
  gateway_api_sha256  = local.environment.locals.gateway_api_sha256

  namespaces = {
    traefik = {
      "gateway-access"                     = "internal"
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
    cert-manager = {
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
    local-path-storage = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
    truenas-csi = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
    cnpg-system = {
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
    authentik = {
      "gateway-access"                     = "internal"
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
    immich = {
      "gateway-access"                     = "internal"
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
    hermes = {
      "gateway-access"                     = "internal"
      "pod-security.kubernetes.io/enforce" = "baseline"
    }
  }
}
