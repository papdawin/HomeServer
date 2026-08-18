provider "authentik" {
  url      = var.authentik_url
  token    = var.authentik_token
  insecure = false
}

data "authentik_flow" "authorization" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "invalidation" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_certificate_key_pair" "signing" {
  name              = "authentik Self-signed Certificate"
  fetch_certificate = false
  fetch_key         = false
}

resource "authentik_provider_oauth2" "immich" {
  name               = "Immich"
  client_id          = var.oidc_client_id
  client_secret      = var.oidc_client_secret
  client_type        = "confidential"
  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id
  issuer_mode        = "per_provider"
  sub_mode           = "hashed_user_id"
  signing_key        = data.authentik_certificate_key_pair.signing.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "${var.immich_url}/auth/login"
    },
    {
      matching_mode = "strict"
      url           = "${var.immich_url}/user-settings"
    },
    {
      matching_mode = "strict"
      url           = "app.immich:///oauth-callback"
    },
  ]
}

resource "authentik_application" "immich" {
  name              = "Immich"
  slug              = "immich"
  protocol_provider = authentik_provider_oauth2.immich.id
  meta_launch_url   = var.immich_url
  meta_description  = "Self-hosted photo and video library"
}

# The bootstrap brand uses a placeholder domain. Set the real public host so proxy
# providers generate browser redirects to Authentik rather than http://localhost.
resource "authentik_brand" "default" {
  domain           = "auth.${var.domain}"
  default          = true
  branding_logo    = "/static/dist/assets/icons/icon_left_brand.svg"
  branding_favicon = "/static/dist/assets/icons/icon.png"
}

data "authentik_outpost" "embedded" {
  name = "authentik Embedded Outpost"
}

resource "authentik_outpost" "embedded" {
  name               = "authentik Embedded Outpost"
  type               = "proxy"
  protocol_providers = [for key in sort(keys(local.arr_apps)) : authentik_provider_proxy.arr[key].id]
  config = jsonencode({
    log_level                        = "info"
    docker_labels                    = null
    authentik_host                   = "https://auth.${var.domain}"
    docker_network                   = null
    container_image                  = null
    docker_map_ports                 = true
    refresh_interval                 = "minutes=5"
    kubernetes_replicas              = 1
    kubernetes_namespace             = "default"
    authentik_host_browser           = "https://auth.${var.domain}"
    object_naming_template           = "ak-outpost-%(name)s"
    authentik_host_insecure          = false
    kubernetes_json_patches          = null
    kubernetes_service_type          = "ClusterIP"
    kubernetes_ingress_path_type     = null
    kubernetes_image_pull_secrets    = []
    kubernetes_ingress_class_name    = null
    kubernetes_disable_x509_strict   = false
    kubernetes_disabled_components   = []
    kubernetes_ingress_annotations   = {}
    kubernetes_ingress_secret_name   = "authentik-outpost-tls"
    kubernetes_httproute_annotations = {}
    kubernetes_httproute_parent_refs = []
  })
}

locals {
  arr_apps = {
    qbittorrent = "qBittorrent"
    radarr      = "Radarr"
    sonarr      = "Sonarr"
    seerr       = "Seerr"
    jellyfin    = "Jellyfin"
    prowlarr    = "Prowlarr"
    hermes      = "Hermes"
  }
}

resource "authentik_provider_proxy" "arr" {
  for_each = local.arr_apps

  name               = each.value
  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id
  external_host      = "https://${each.key}.${var.domain}"
  mode               = "forward_domain"
}

resource "authentik_application" "arr" {
  for_each = local.arr_apps

  name              = each.value
  slug              = each.key
  protocol_provider = authentik_provider_proxy.arr[each.key].id
  meta_launch_url   = "https://${each.key}.${var.domain}"
  meta_description  = "Homelab ${each.value}"
}

resource "authentik_outpost_provider_attachment" "arr" {
  for_each = local.arr_apps

  outpost           = authentik_outpost.embedded.id
  protocol_provider = authentik_provider_proxy.arr[each.key].id
}

output "issuer_url" {
  value = "${var.authentik_url}/application/o/immich/"
}
