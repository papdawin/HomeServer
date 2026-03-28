inputs = {
  proxmox_node = {
    name       = "server"
    api_url    = "https://192.168.68.4:8006/"
    enabled    = true
    verify_tls = false
  }

  network = {
    bridge        = "vmbr0"
    gateway_ipv4  = "192.168.68.1"
    dns_servers   = ["1.1.1.1", "8.8.8.8"]
    dns_search    = "lan"
    vlan_id       = null
    mtu           = null
    firewall      = true
    rate_limit_mb = null
  }

  lxc_defaults = {
    start_on_boot            = true
    started                  = true
    unprivileged             = true
    protection               = false
    tags                     = ["lxc", "terraform-managed"]
    rootfs_datastore_default = "local-lvm"
    rootfs_size_gb_default   = 8
    cpu_cores_default        = 2
    memory_mb_default        = 2048
    template_datastore       = "local"
    template_file_name       = "ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    template_url             = "http://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    template_checksum        = ""
    cpu_units                = 1024
    cpu_limit                = null
    swap_mb                  = 512
    startup_order            = "3"
    startup_up_delay         = "30"
    startup_down_delay       = "30"
  }
}
