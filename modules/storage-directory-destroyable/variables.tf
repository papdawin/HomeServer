variable "storage_id" {
  type = string

  validation {
    condition     = trimspace(var.storage_id) != ""
    error_message = "storage_id must be non-empty."
  }
}

variable "path" {
  type = string

  validation {
    condition     = trimspace(var.path) != ""
    error_message = "path must be non-empty."
  }
}

variable "nodes" {
  type = list(string)

  validation {
    condition = length(var.nodes) > 0 && alltrue([
      for node in var.nodes : trimspace(node) != ""
    ])
    error_message = "nodes must contain at least one non-empty node name."
  }
}

variable "content_types" {
  type    = list(string)
  default = ["rootdir"]
}

variable "shared" {
  type    = bool
  default = false
}

variable "disable" {
  type    = bool
  default = false
}

variable "preallocation" {
  type    = string
  default = ""
}
