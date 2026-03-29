locals {
  pm_api_url_raw        = get_env("PM_API_URL", "https://192.168.68.4:8006/api2/json")
  pm_api_base_url       = trimsuffix(local.pm_api_url_raw, "/api2/json")
  pm_endpoint           = endswith(local.pm_api_base_url, "/") ? local.pm_api_base_url : "${local.pm_api_base_url}/"
  pm_tls_insecure       = lower(get_env("PM_TLS_INSECURE", "true")) == "true"
  pm_api_token_id       = get_env("PM_API_TOKEN_ID", "")
  pm_api_token_secret   = get_env("PM_API_TOKEN_SECRET", "")
  pm_api_token_combined = local.pm_api_token_id != "" && local.pm_api_token_secret != "" ? "${local.pm_api_token_id}=${local.pm_api_token_secret}" : local.pm_api_token_id
}

remote_state {
  backend = "local"
  config = {
    path = "${get_repo_root()}/.tfstate/${path_relative_to_include()}.tfstate"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.98"
    }
  }
}

provider "proxmox" {
  endpoint  = "${local.pm_endpoint}"
  insecure  = ${local.pm_tls_insecure}
  api_token = "${local.pm_api_token_combined}"
}
EOF
}
