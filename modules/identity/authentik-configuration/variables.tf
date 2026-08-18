variable "authentik_url" {
  type = string
}

variable "authentik_token" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "oidc_client_id" {
  type      = string
  sensitive = true
}

variable "oidc_client_secret" {
  type      = string
  sensitive = true
}

variable "immich_url" {
  type = string
}

variable "domain" {
  type = string
}
