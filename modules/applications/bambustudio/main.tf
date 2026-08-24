locals {
  hostname = "bambustudio.${var.domain}"
  labels   = { "app.kubernetes.io/name" = "bambustudio", "app.kubernetes.io/part-of" = "bambustudio", "app.kubernetes.io/managed-by" = "terraform" }

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
      metadata   = { name = "bambustudio", namespace = var.namespace, labels = local.labels }
      spec = {
        replicas = 1
        strategy = { type = "Recreate" }
        selector = { matchLabels = { app = "bambustudio" } }
        template = {
          metadata = { labels = merge(local.labels, { app = "bambustudio" }) }
          spec = {
            automountServiceAccountToken = false
            containers = [{
              name  = "bambustudio"
              image = "lscr.io/linuxserver/bambustudio:latest"
              ports = [{ name = "http", containerPort = 3000 }, { name = "https", containerPort = 3001 }]
              env = [
                { name = "PUID", value = "3007" },
                { name = "PGID", value = "3007" },
                { name = "TZ", value = "Europe/Brussels" },
                { name = "DARK_MODE", value = "true" },
                { name = "HARDEN_DESKTOP", value = "true" },
                { name = "SELKIES_FILE_TRANSFERS", value = "upload,download" },
                { name = "SELKIES_UI_SIDEBAR_SHOW_FILES", value = "true" },
                { name = "MAX_RES", value = "1920x1080" },
              ]
              resources = { requests = { cpu = "500m", memory = "1Gi" }, limits = { cpu = "2", memory = "3Gi" } }
              volumeMounts = [
                { name = "runtime-config", mountPath = "/config" },
                { name = "shared-files", mountPath = "/config/Desktop" },
                { name = "shm", mountPath = "/dev/shm" },
              ]
              readinessProbe = { tcpSocket = { port = "http" }, initialDelaySeconds = 60, periodSeconds = 10, timeoutSeconds = 5, failureThreshold = 24 }
              livenessProbe  = { tcpSocket = { port = "http" }, initialDelaySeconds = 180, periodSeconds = 20, timeoutSeconds = 5, failureThreshold = 6 }
            }]
            volumes = [
              { name = "runtime-config", persistentVolumeClaim = { claimName = kubernetes_persistent_volume_claim_v1.runtime_config.metadata[0].name } },
              { name = "shared-files", persistentVolumeClaim = { claimName = "bambustudio-config" } },
              { name = "shm", emptyDir = { medium = "Memory", sizeLimit = "1Gi" } },
            ]
          }
        }
      }
    })
    service = yamlencode({ apiVersion = "v1", kind = "Service", metadata = { name = "bambustudio", namespace = var.namespace, labels = local.labels }, spec = { selector = { app = "bambustudio" }, ports = [{ name = "http", port = 3000, targetPort = "http" }] } })
    route   = yamlencode({ apiVersion = "traefik.io/v1alpha1", kind = "IngressRoute", metadata = { name = "bambustudio", namespace = var.namespace, labels = local.labels }, spec = { entryPoints = ["websecure"], routes = [{ kind = "Rule", match = "Host(`${local.hostname}`)", middlewares = [{ name = "authentik" }], services = [{ name = "bambustudio", port = 3000 }] }], tls = {} } })
  }
}

# Bambu Studio uses local runtime locks and databases which block on NFS.
# NFS remains mounted below at /config/Desktop for durable file transfers.
resource "kubernetes_persistent_volume_claim_v1" "runtime_config" {
  wait_until_bound = false

  metadata {
    name      = "bambustudio-runtime"
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-ssd"

    resources {
      requests = { storage = "20Gi" }
    }
  }
}

resource "kubectl_manifest" "this" {
  for_each          = local.manifests
  yaml_body         = each.value
  server_side_apply = true
  field_manager     = "terraform-bambustudio"
  wait_for_rollout  = each.key == "deployment"
  depends_on        = [kubernetes_persistent_volume_claim_v1.runtime_config]
}

output "url" { value = "https://${local.hostname}" }
