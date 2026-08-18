variable "worker_node" {
  type = string
}

variable "control_plane_node" {
  type = string
}

variable "worker_address" {
  type = string
}

variable "control_plane_address" {
  type = string
}

variable "truenas_address" {
  type = string
}

variable "truenas_pool" {
  type = string
}

variable "truenas_csi_version" {
  type = string
}

variable "truenas_csi_commit" {
  type = string
}

variable "truenas_csi_sha256" {
  type = string
}

variable "local_path_version" {
  type = string
}

variable "truenas_api_key" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "secret_revision" {
  type = number
}

variable "truenas_credential_rotated" {
  type        = bool
  default     = false
  description = "Explicit acknowledgement that the API key exposed in chat was revoked and replaced."
}
