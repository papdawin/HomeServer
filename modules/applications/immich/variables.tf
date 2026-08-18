variable "chart_version" {
  type = string
}

variable "image_version" {
  type = string
}

variable "domain" {
  type = string
}

variable "oidc_client_id" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "oidc_client_secret" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "secret_revision" {
  type = number
}

variable "machine_learning_node" {
  type = string
}

variable "namespace" {
  type    = string
  default = "immich"
}
