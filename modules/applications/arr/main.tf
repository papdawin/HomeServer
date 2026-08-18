locals {
  apps = {
    qbittorrent = { image = "lscr.io/linuxserver/qbittorrent:5.1.4", port = 8080, config = "qbittorrent", mounts = ["downloads"] }
    radarr      = { image = "lscr.io/linuxserver/radarr:6.3.0", port = 7878, config = "radarr", mounts = ["media", "downloads"] }
    sonarr      = { image = "lscr.io/linuxserver/sonarr:4.0.15", port = 8989, config = "sonarr", mounts = ["media", "downloads"] }
    prowlarr    = { image = "lscr.io/linuxserver/prowlarr:2.3.0", port = 9696, config = "prowlarr", mounts = [] }
    seerr       = { image = "fallenbagel/jellyseerr:2.7.3", port = 5055, config = "seerr", config_mount = "/app/config", mounts = [] }
    jellyfin    = { image = "jellyfin/jellyfin:10.10.7", port = 8096, config = "jellyfin", mounts = ["media"] }
  }

  manifests = merge(
    {
      middleware = yamlencode({
        apiVersion = "traefik.io/v1alpha1"
        kind       = "Middleware"
        metadata   = { name = "authentik", namespace = var.namespace }
        spec = { forwardAuth = {
          address             = "http://authentik-server.authentik.svc.cluster.local/outpost.goauthentik.io/auth/traefik"
          trustForwardHeader  = true
          authResponseHeaders = ["X-authentik-username", "X-authentik-groups", "X-authentik-email", "X-authentik-name", "X-authentik-uid", "X-authentik-jwt"]
          authSigninURL       = "${var.authentik_url}/outpost.goauthentik.io/start?rd={url}"
        } }
      })
    },
    { for name, app in local.apps : "deployment-${name}" => yamlencode({
      apiVersion = "apps/v1"
      kind       = "Deployment"
      metadata   = { name = name, namespace = var.namespace, labels = { "app.kubernetes.io/name" = name, "app.kubernetes.io/part-of" = "arr" } }
      spec = {
        replicas = 1
        # One replica and no surge prevents concurrent writers to shared NFS-backed state.
        strategy = { type = "RollingUpdate", rollingUpdate = { maxSurge = 0, maxUnavailable = 1 } }
        selector = { matchLabels = { app = name } }
        template = {
          metadata = { labels = { app = name, "app.kubernetes.io/name" = name } }
          spec = {
            securityContext = { fsGroup = 1000, seccompProfile = { type = "RuntimeDefault" } }
            initContainers = [{
              name            = "initialize-config"
              image           = "busybox:1.37"
              command         = ["sh", "-ec", "mkdir -p /appdata/${app.config}; test ! -e /appdata/${app.config}/config.xml || test -s /appdata/${app.config}/config.xml || rm -f /appdata/${app.config}/config.xml"]
              volumeMounts    = [{ name = "appdata", mountPath = "/appdata" }]
              securityContext = { allowPrivilegeEscalation = false, capabilities = { drop = ["ALL"] } }
            }]
            containers = [{
              name  = name
              image = app.image
              ports = concat([{ name = "http", containerPort = app.port }], name == "qbittorrent" ? [{ name = "bittorrent-tcp", containerPort = 6881, protocol = "TCP" }, { name = "bittorrent-udp", containerPort = 6881, protocol = "UDP" }] : [])
              env = concat([
                { name = "PUID", value = "1000" }, { name = "PGID", value = "1000" }, { name = "TZ", value = "Europe/Brussels" }
              ], name == "jellyfin" ? [{ name = "JELLYFIN_PublishedServerUrl", value = "https://jellyfin.${var.domain}" }] : [])
              # Shared absolute paths preserve atomic imports/hardlink eligibility across the media services.
              volumeMounts = concat([{ name = "appdata", mountPath = try(app.config_mount, "/config"), subPath = app.config }], [for volume in app.mounts : { name = volume, mountPath = "/data/${volume}" }])
              # Radarr/Sonarr migrate SQLite on first start over NFS; don't restart them mid-migration.
              startupProbe   = { httpGet = { path = "/", port = "http" }, periodSeconds = 10, failureThreshold = 90 }
              readinessProbe = { httpGet = { path = "/", port = "http" }, periodSeconds = 10, failureThreshold = 12 }
              livenessProbe  = { httpGet = { path = "/", port = "http" }, periodSeconds = 20, failureThreshold = 6 }
              # LinuxServer images start as root, then drop to PUID/PGID themselves.
              securityContext = contains(["qbittorrent", "radarr", "sonarr", "prowlarr"], name) ? null : { allowPrivilegeEscalation = false, capabilities = { drop = ["ALL"] } }
            }]
            volumes = concat([{ name = "appdata", persistentVolumeClaim = { claimName = "arr-appdata" } }], [for volume in app.mounts : { name = volume, persistentVolumeClaim = { claimName = "arr-${volume}" } }])
          }
        }
      }
    }) },
    { for name, app in local.apps : "service-${name}" => yamlencode({
      apiVersion = "v1"
      kind       = "Service"
      metadata   = { name = name, namespace = var.namespace }
      spec       = { selector = { app = name }, ports = concat([{ name = "http", port = app.port, targetPort = "http" }], name == "qbittorrent" ? [{ name = "bittorrent-tcp", port = 6881, targetPort = "bittorrent-tcp", protocol = "TCP" }, { name = "bittorrent-udp", port = 6881, targetPort = "bittorrent-udp", protocol = "UDP" }] : []) }
    }) },
    {
      # TV/app clients can't complete Authentik's browser login, so give Jellyfin a
      # second LAN-only entry point that skips Traefik/Authentik entirely.
      service-jellyfin-lan = yamlencode({
        apiVersion = "v1"
        kind       = "Service"
        metadata   = { name = "jellyfin-lan", namespace = var.namespace }
        spec = {
          type     = "NodePort"
          selector = { app = "jellyfin" }
          ports    = [{ name = "http", port = local.apps.jellyfin.port, targetPort = "http", nodePort = 30096 }]
        }
      })
    },
    { for name, app in local.apps : "route-${name}" => yamlencode({
      apiVersion = "traefik.io/v1alpha1"
      kind       = "IngressRoute"
      metadata   = { name = name, namespace = var.namespace }
      spec = {
        entryPoints = ["websecure"]
        routes = [{
          kind        = "Rule"
          match       = "Host(`${name}.${var.domain}`)"
          middlewares = [{ name = "authentik" }]
          services    = [{ name = name, port = app.port }]
        }]
        tls = {}
      }
    }) }
  )
}

resource "kubectl_manifest" "arr" {
  for_each          = local.manifests
  yaml_body         = each.value
  server_side_apply = true
  field_manager     = "terraform-arr"
  wait_for_rollout  = startswith(each.key, "deployment-")
}

output "urls" { value = [for name in keys(local.apps) : "https://${name}.${var.domain}"] }
