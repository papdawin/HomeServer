locals {
  kubeconfig_path = get_env("KUBECONFIG", "${get_env("HOME")}/homelab/talos/kubeconfig")
  kube_context    = "admin@pdwncluster"

  cluster_name = "pdwncluster"
  domain       = "home.papdavid.eu"
  dns_zone     = "papdavid.eu"
  acme_email   = "papdavid98@gmail.com"

  worker_node        = "talos1"
  worker_address     = "192.168.68.6"
  control_plane_node = "talos2"
  control_plane_ip   = "192.168.68.7"

  truenas_address = "192.168.68.120"
  truenas_pool    = "HDD"

  gateway_api_version = "v1.6.1"
  gateway_api_sha256  = "24d931f22abd8e40c973264319ead7cfa09d0fb7716b7ab1ee2ff174cb063a73"

  traefik_chart_version      = "41.2.0"
  cert_manager_chart_version = "v1.21.1"
  cnpg_chart_version         = "0.29.0"
  authentik_chart_version    = "2026.5.6"
  immich_chart_version       = "0.13.1"

  local_path_version   = "v0.0.37"
  truenas_csi_version  = "v1.1.2"
  truenas_csi_commit   = "d5fddc049d1cc80da9bb1f37569a8b49a7956dce"
  truenas_csi_sha256   = "672e228ad4d3fa3216dd237f3ab5a2aa7f3ebfc68fa6b5e035a02a923af217c9"
  postgresql_image     = "ghcr.io/cloudnative-pg/postgresql:18-standard-trixie"
  vectorchord_image    = "ghcr.io/tensorchord/vchord-scratch:pg18-v1.1.1"
  immich_image_version = "v3.1.0"

  secrets_directory = "${get_repo_root()}/secrets"
}
