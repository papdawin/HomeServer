variable "namespace" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "database_name" {
  type = string
}

variable "database_owner" {
  type = string
}

variable "credentials_secret_name" {
  type = string
}

variable "secret_data" {
  type      = map(string)
  sensitive = true
  ephemeral = true
}

variable "secret_revision" {
  type = number
}

variable "postgresql_image" {
  type = string
}

variable "vectorchord_image" {
  type    = string
  default = null
}

variable "enable_immich_extensions" {
  type    = bool
  default = false
}

variable "storage_size" {
  type = string
}

variable "node_name" {
  type = string
}

variable "resources" {
  type = object({
    requests = map(string)
    limits   = map(string)
  })
}

variable "backup_pvc_name" {
  type = string
}

variable "backup_schedule" {
  type = string
}
