locals {
  pm_api_url_raw        = get_env("PM_API_URL", "https://192.168.68.4:8006/api2/json")
  pm_api_base_url       = trimsuffix(local.pm_api_url_raw, "/api2/json")
  pm_endpoint           = endswith(local.pm_api_base_url, "/") ? local.pm_api_base_url : "${local.pm_api_base_url}/"
  pm_tls_insecure       = lower(get_env("PM_TLS_INSECURE", "true")) == "true"
  pm_api_token_id       = get_env("PM_API_TOKEN_ID", "")
  pm_api_token_secret   = get_env("PM_API_TOKEN_SECRET", "")
  pm_api_token_combined = local.pm_api_token_id != "" && local.pm_api_token_secret != "" ? "${local.pm_api_token_id}=${local.pm_api_token_secret}" : local.pm_api_token_id
  pm_username           = trimspace(get_env("PM_USERNAME", ""))
  pm_password           = get_env("PM_PASSWORD", "")
  pm_use_password_auth  = local.pm_username != "" && local.pm_password != ""
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
      version = "~> 0.106"
    }
  }
}

provider "proxmox" {
  endpoint  = "${local.pm_endpoint}"
  insecure  = ${local.pm_tls_insecure}
  username  = ${jsonencode(local.pm_use_password_auth ? local.pm_username : null)}
  password  = ${jsonencode(local.pm_use_password_auth ? local.pm_password : null)}
  api_token = ${jsonencode(!local.pm_use_password_auth && local.pm_api_token_combined != "" ? local.pm_api_token_combined : null)}
}
EOF
}

terraform {
  # Prevent interactive Terraform prompts in all Terragrunt modules.
  extra_arguments "disable_input" {
    commands  = get_terraform_commands_that_need_input()
    arguments = ["-input=false"]
  }

  # Optional: set TG_AUTO_APPROVE=true for unattended apply/destroy.
  extra_arguments "auto_approve" {
    commands  = ["apply", "destroy"]
    arguments = lower(trimspace(get_env("TG_AUTO_APPROVE", "false"))) == "true" ? ["-auto-approve"] : []
  }
}
