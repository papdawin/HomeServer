locals {
  kubeconfig_path = get_env("KUBECONFIG", "${get_env("HOME")}/homelab/talos/kubeconfig")
  kube_context    = "admin@pdwncluster"
  state_path      = "${get_repo_root()}/.terragrunt-state/${path_relative_to_include()}/terraform.tfstate"
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      backend "local" {
        path = "${local.state_path}"
      }
    }
  EOF
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    variable "kubeconfig_path" {
      type        = string
      description = "Path to the Talos-generated kubeconfig."
    }

    variable "kube_context" {
      type        = string
      description = "Kubernetes context that Terraform is allowed to manage."
    }

    provider "kubernetes" {
      config_path    = var.kubeconfig_path
      config_context = var.kube_context
    }

    provider "helm" {
      kubernetes = {
        config_path    = var.kubeconfig_path
        config_context = var.kube_context
      }
    }

    provider "kubectl" {
      config_path      = var.kubeconfig_path
      config_context   = var.kube_context
      load_config_file = true
    }

  EOF
}

inputs = {
  kubeconfig_path = local.kubeconfig_path
  kube_context    = local.kube_context
}
