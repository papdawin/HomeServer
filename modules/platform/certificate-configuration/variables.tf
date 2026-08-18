variable "cloudflare_api_token" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "secret_revision" {
  type = number
}

variable "domain" {
  type = string
}

variable "dns_zone" {
  type = string
}

variable "acme_email" {
  type = string
}

variable "certificate_issuer_name" {
  type    = string
  default = "letsencrypt-staging"

  validation {
    condition     = contains(["letsencrypt-staging", "letsencrypt-production"], var.certificate_issuer_name)
    error_message = "certificate_issuer_name must select the staging or production issuer."
  }
}
