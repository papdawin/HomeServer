variable "gateway_api_version" {
  type = string
}

variable "gateway_api_sha256" {
  type = string

  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.gateway_api_sha256))
    error_message = "gateway_api_sha256 must be a lowercase SHA-256 digest."
  }
}

variable "namespaces" {
  type = map(map(string))
}
