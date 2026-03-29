variable "target_node" {
  type = string
}

variable "vmid" {
  type = number
}

variable "hostname" {
  type = string
}

variable "ostemplate" {
  type = string
}

variable "ostype" {
  type    = string
  default = "unmanaged"
}

variable "lxc_password" {
  type      = string
  sensitive = true

  validation {
    condition     = length(var.lxc_password) > 0
    error_message = "Set LXC_PASSWORD before planning/applying."
  }
}

variable "unprivileged" {
  type    = bool
  default = true
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 2048
}

variable "swap" {
  type    = number
  default = 512
}

variable "start" {
  type    = bool
  default = true
}

variable "onboot" {
  type    = bool
  default = true
}

variable "rootfs_storage" {
  type = string
}

variable "rootfs_size" {
  type    = string
  default = "32G"
}

variable "bridge" {
  type = string
}

variable "ipv4_cidr" {
  type = string

  validation {
    condition = (
      var.ipv4_cidr == trimspace(var.ipv4_cidr) &&
      can(regex("^((25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})\\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})/(3[0-2]|[12]?[0-9])$", trimspace(var.ipv4_cidr)))
    )
    error_message = "ipv4_cidr must be an IPv4 CIDR (example: 192.168.68.25/24) without leading/trailing whitespace."
  }
}

variable "gateway" {
  type = string

  validation {
    condition = (
      var.gateway == trimspace(var.gateway) &&
      can(regex("^((25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})\\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})$", trimspace(var.gateway)))
    )
    error_message = "gateway must be an IPv4 address without leading/trailing whitespace (example: 192.168.68.1)."
  }
}

variable "ssh_public_keys" {
  type    = string
  default = ""
}

variable "features_nesting" {
  type    = bool
  default = false
}

variable "features_keyctl" {
  type    = bool
  default = false
}

variable "features_fuse" {
  type    = bool
  default = false
}

variable "features_mount" {
  type    = string
  default = ""
}

variable "flake_file" {
  type    = string
  default = ""
}

variable "flake_attr" {
  type    = string
  default = "jellyfin"
}

variable "bootstrap_use_ssh_agent" {
  type    = bool
  default = true
}
