variable "node_name" {
  description = "Target Proxmox node."
  type        = string
}

variable "ct_id" {
  description = "Container VMID."
  type        = number
}

variable "hostname" {
  description = "Container hostname."
  type        = string
}

variable "description" {
  description = "Container description."
  type        = string
}

variable "template_file_id" {
  description = "Template file ID for the operating system."
  type        = string
}

variable "start_on_boot" {
  description = "Whether to start this container on host boot."
  type        = bool
  default     = true
}

variable "started" {
  description = "Whether the container should be running."
  type        = bool
  default     = true
}

variable "unprivileged" {
  description = "Run container as unprivileged."
  type        = bool
  default     = true
}

variable "protection" {
  description = "Enable Proxmox protection flag."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Container tags."
  type        = list(string)
  default     = []
}

variable "cpu_cores" {
  description = "CPU cores."
  type        = number
}

variable "cpu_units" {
  description = "CPU units/shares."
  type        = number
  default     = 1024
}

variable "cpu_limit" {
  description = "CPU limit."
  type        = number
  default     = null
}

variable "memory_mb" {
  description = "Dedicated memory in MiB."
  type        = number
}

variable "swap_mb" {
  description = "Swap in MiB."
  type        = number
  default     = 0
}

variable "rootfs_datastore" {
  description = "Datastore for root filesystem."
  type        = string
}

variable "rootfs_size_gb" {
  description = "Root filesystem size in GiB."
  type        = number
}

variable "network" {
  description = "Primary container network setup."
  type = object({
    interface     = string
    bridge        = string
    ipv4_cidr     = string
    ipv4_gateway  = string
    firewall      = bool
    vlan_id       = optional(number)
    mtu           = optional(number)
    rate_limit_mb = optional(number)
    dns_servers   = list(string)
    dns_search    = string
  })
}

variable "startup" {
  description = "Startup order and delays."
  type = object({
    order      = string
    up_delay   = string
    down_delay = string
  })
}

variable "ssh_public_keys" {
  description = "Root user SSH public keys."
  type        = list(string)
}

variable "user_password" {
  description = "Root user password for initial container login."
  type        = string
  default     = null
  sensitive   = true
}

variable "bootstrap_commands" {
  description = "Optional commands to run via SSH after container creation."
  type        = list(string)
  default     = []
}

variable "mount_points" {
  description = "Extra mount points."
  type = list(object({
    path          = string
    volume        = string
    size          = optional(string)
    read_only     = optional(bool)
    backup        = optional(bool)
    replicate     = optional(bool)
    shared        = optional(bool)
    mount_options = optional(list(string))
  }))
  default = []
}

variable "device_passthrough" {
  description = "Optional device passthrough blocks."
  type = list(object({
    path       = string
    uid        = optional(number)
    gid        = optional(number)
    mode       = optional(string)
    deny_write = optional(bool)
  }))
  default = []
}
