locals {
  hostname = "homeassistant.${var.domain}"
  labels   = { "app.kubernetes.io/name" = "homeassistant", "app.kubernetes.io/part-of" = "homeassistant", "app.kubernetes.io/managed-by" = "terraform" }

  manifests = {
    middleware = yamlencode({
      apiVersion = "traefik.io/v1alpha1"
      kind       = "Middleware"
      metadata   = { name = "authentik", namespace = var.namespace, labels = local.labels }
      spec = { forwardAuth = {
        address             = "http://authentik-server.authentik.svc.cluster.local/outpost.goauthentik.io/auth/traefik"
        trustForwardHeader  = true
        authResponseHeaders = ["X-authentik-username", "X-authentik-groups", "X-authentik-email", "X-authentik-name", "X-authentik-uid", "X-authentik-jwt"]
        authSigninURL       = "${var.authentik_url}/outpost.goauthentik.io/start?rd={url}"
      } }
    })
    deployment = yamlencode({
      apiVersion = "apps/v1"
      kind       = "Deployment"
      metadata   = { name = "homeassistant", namespace = var.namespace, labels = local.labels }
      spec = {
        replicas = 1
        strategy = { type = "Recreate" }
        selector = { matchLabels = { app = "homeassistant" } }
        template = {
          metadata = { labels = merge(local.labels, { app = "homeassistant" }) }
          spec = {
            automountServiceAccountToken = false
            hostNetwork                  = true
            dnsPolicy                    = "ClusterFirstWithHostNet"
            nodeSelector                 = { "kubernetes.io/hostname" = "talos1" }
            initContainers = [{
              name         = "seed-config"
              image        = "busybox:1.37"
              command      = ["sh", "-ec", "if [ ! -e /config/configuration.yaml ]; then printf '%s\\n' 'default_config:' '' 'http:' '  use_x_forwarded_for: true' '  trusted_proxies:' '    - 192.168.68.6' '    - 192.168.68.7' > /config/configuration.yaml; fi"]
              volumeMounts = [{ name = "config", mountPath = "/config" }]
            }]
            containers = [{
              name  = "homeassistant"
              image = "ghcr.io/home-assistant/home-assistant:2026.8.2"
              ports = [{ name = "http", containerPort = 8123 }]
              resources = {
                requests = { cpu = "250m", memory = "512Mi" }
                limits   = { cpu = "2", memory = "2Gi" }
              }
              volumeMounts   = [{ name = "config", mountPath = "/config" }]
              readinessProbe = { tcpSocket = { port = "http" }, initialDelaySeconds = 30, periodSeconds = 10, timeoutSeconds = 5, failureThreshold = 30 }
              livenessProbe  = { tcpSocket = { port = "http" }, initialDelaySeconds = 120, periodSeconds = 20, timeoutSeconds = 5, failureThreshold = 6 }
            }]
            volumes = [{ name = "config", persistentVolumeClaim = { claimName = "homeassistant-config" } }]
          }
        }
      }
    })
    service = yamlencode({ apiVersion = "v1", kind = "Service", metadata = { name = "homeassistant", namespace = var.namespace, labels = local.labels }, spec = { selector = { app = "homeassistant" }, ports = [{ name = "http", port = 8123, targetPort = "http" }] } })
    route   = yamlencode({ apiVersion = "traefik.io/v1alpha1", kind = "IngressRoute", metadata = { name = "homeassistant", namespace = var.namespace, labels = local.labels }, spec = { entryPoints = ["websecure"], routes = [{ kind = "Rule", match = "Host(`${local.hostname}`)", middlewares = [{ name = "authentik" }], services = [{ name = "homeassistant", port = 8123 }] }], tls = {} } })
  }
}

resource "kubectl_manifest" "this" {
  for_each          = local.manifests
  yaml_body         = each.value
  server_side_apply = true
  field_manager     = "terraform-homeassistant"
  wait_for_rollout  = each.key == "deployment"
}

output "url" { value = "https://${local.hostname}" }
