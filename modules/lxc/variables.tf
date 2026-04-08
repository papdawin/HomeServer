variable "target_node" {
  type = string
}

variable "vmid" {
  type = number
}

variable "hostname" {
  type = string
}

variable "tags" {
  description = "Container tags shown in Proxmox UI."
  type        = list(string)
  default     = []

  validation {
    condition = (
      length(var.tags) <= 4 &&
      alltrue([
        for tag in var.tags :
        trimspace(tag) != "" &&
        can(regex("^[a-z0-9][a-z0-9_-]*$", lower(trimspace(tag))))
      ])
    )
    error_message = "tags must contain up to 4 lowercase alphanumeric tags (allowed: _ and -)."
  }
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

variable "common_sops_file" {
  type = string
}

variable "bootstrap_private_key_file" {
  type = string
}

variable "mount_points" {
  description = "Additional LXC mount points (bind mounts or extra volumes)."
  type = list(object({
    path   = string
    volume = string
    size   = optional(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for mount_point in var.mount_points :
      trimspace(mount_point.path) != "" &&
      trimspace(mount_point.volume) != "" &&
      (
        try(mount_point.size, null) == null ||
        trimspace(try(mount_point.size, "")) != ""
      )
    ])
    error_message = "Each mount point must define non-empty path and volume values. If size is set, it must be non-empty."
  }
}

variable "post_rebuild_commands" {
  description = "Optional commands executed on the container after nixos-rebuild switch."
  type        = list(string)
  default     = []
}
