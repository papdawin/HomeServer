locals {
  terraform_version_constraint = ">= 1.6.0"
  proxmox_provider_version     = "~> 0.95.0"
}

generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = "${local.terraform_version_constraint}"

      required_providers {
        proxmox = {
          source  = "bpg/proxmox"
          version = "${local.proxmox_provider_version}"
        }
      }
    }
  EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "proxmox" {
      endpoint  = var.proxmox_node.api_url
      api_token = format("%s=%s", var.api_token_id, var.api_token_secret)
      insecure  = !var.proxmox_node.verify_tls
    }
  EOF
}

inputs = {
  api_token_id     = get_env("PVE_API_TOKEN_ID", "")
  api_token_secret = get_env("PVE_API_TOKEN_SECRET", "")
}
