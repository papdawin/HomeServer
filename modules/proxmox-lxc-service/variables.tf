variable "proxmox_node" {
  description = "Target Proxmox node metadata."
  type = object({
    name       = string
    api_url    = string
    enabled    = bool
    verify_tls = bool
  })
}

variable "api_token_id" {
  description = "Proxmox API token ID (e.g. terraform@pve!provider)."
  type        = string
  sensitive   = true
  validation {
    condition     = length(trimspace(var.api_token_id)) > 0
    error_message = "api_token_id must be provided (set PVE_API_TOKEN_ID)."
  }
}

variable "api_token_secret" {
  description = "Proxmox API token secret."
  type        = string
  sensitive   = true
  validation {
    condition     = length(trimspace(var.api_token_secret)) > 0
    error_message = "api_token_secret must be provided (set PVE_API_TOKEN_SECRET)."
  }
}

variable "network" {
  description = "Default network values for LXC containers."
  type = object({
    bridge        = string
    gateway_ipv4  = string
    dns_servers   = list(string)
    dns_search    = string
    vlan_id       = optional(number)
    mtu           = optional(number)
    firewall      = bool
    rate_limit_mb = optional(number)
  })
}

variable "lxc_defaults" {
  description = "Default LXC behavior and template download settings."
  type = object({
    start_on_boot            = bool
    started                  = bool
    unprivileged             = bool
    protection               = bool
    tags                     = list(string)
    rootfs_datastore_default = string
    rootfs_size_gb_default   = number
    cpu_cores_default        = number
    memory_mb_default        = number
    template_datastore       = string
    template_file_name       = string
    template_url             = string
    template_checksum        = string
    cpu_units                = number
    cpu_limit                = optional(number)
    swap_mb                  = number
    startup_order            = string
    startup_up_delay         = string
    startup_down_delay       = string
  })
}

variable "containers" {
  description = "Map of LXC container definitions keyed by logical name."
  type = map(object({
    enabled            = optional(bool, true)
    ct_id              = number
    hostname           = string
    description        = optional(string)
    rootfs_datastore   = optional(string)
    rootfs_size_gb     = optional(number)
    cpu_cores          = optional(number)
    memory_mb          = optional(number)
    static_ipv4_cidr   = string
    tags               = optional(list(string), [])
    ssh_public_keys    = optional(list(string), [])
    user_password      = optional(string)
    bootstrap_commands = optional(list(string), [])
    mount_points = optional(list(object({
      path          = string
      volume        = string
      size          = optional(string)
      read_only     = optional(bool)
      backup        = optional(bool)
      replicate     = optional(bool)
      shared        = optional(bool)
      mount_options = optional(list(string))
    })), [])
    device_passthrough = optional(list(object({
      path       = string
      uid        = optional(number)
      gid        = optional(number)
      mode       = optional(string)
      deny_write = optional(bool)
    })), [])
  }))
  default = {}

  validation {
    condition     = length(distinct([for container in values(var.containers) : container.ct_id])) == length(var.containers)
    error_message = "Each container ct_id must be unique."
  }

  validation {
    condition     = alltrue([for container in values(var.containers) : can(cidrhost(container.static_ipv4_cidr, 0))])
    error_message = "Each container.static_ipv4_cidr must be a valid CIDR address (e.g. 192.168.1.50/24)."
  }
}
