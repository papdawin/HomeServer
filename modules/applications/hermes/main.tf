locals {
  hostname = "hermes.${var.domain}"
  labels   = { "app.kubernetes.io/part-of" = "hermes", "app.kubernetes.io/managed-by" = "terraform" }

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
    source-init = yamlencode({
      apiVersion = "apps/v1"
      kind       = "Deployment"
      metadata   = { name = "hermes", namespace = var.namespace, labels = local.labels }
      spec = {
        replicas = 1
        strategy = { type = "Recreate" }
        selector = { matchLabels = { app = "hermes" } }
        template = {
          metadata = { labels = merge(local.labels, { app = "hermes" }) }
          spec = {
            automountServiceAccountToken = false
            initContainers = [{
              name         = "copy-agent-source"
              image        = "nousresearch/hermes-agent:latest"
              command      = ["sh", "-ec", "cp -a /opt/hermes/. /agent-src/"]
              volumeMounts = [{ name = "agent-source", mountPath = "/agent-src" }]
            }]
            containers = [
              {
                name    = "agent"
                image   = "nousresearch/hermes-agent:latest"
                command = ["hermes", "gateway", "run"]
                ports   = [{ name = "api", containerPort = 8642 }]
                env = [
                  { name = "HERMES_HOME", value = "/home/hermes/.hermes" },
                  { name = "HERMES_UID", value = "3004" }, { name = "HERMES_GID", value = "3004" },
                ]
                resources    = { requests = { cpu = "100m", memory = "256Mi" }, limits = { cpu = "1", memory = "1Gi" } }
                volumeMounts = [{ name = "home", mountPath = "/home/hermes/.hermes" }, { name = "agent-source", mountPath = "/opt/hermes" }]
              },
              {
                name  = "webui"
                image = "ghcr.io/nesquena/hermes-webui:latest"
                ports = [{ name = "http", containerPort = 8787 }]
                env = [
                  { name = "HERMES_WEBUI_HOST", value = "0.0.0.0" }, { name = "HERMES_WEBUI_PORT", value = "8787" },
                  { name = "HERMES_WEBUI_STATE_DIR", value = "/home/hermeswebui/.hermes/webui" },
                  { name = "WANTED_UID", value = "3004" }, { name = "WANTED_GID", value = "3004" },
                  { name = "HERMES_WEBUI_SECURE", value = "1" }, { name = "HERMES_WEBUI_TRUST_FORWARDED_HOST", value = "1" }, { name = "HERMES_WEBUI_TRUST_FORWARDED_PROTO", value = "1" },
                  { name = "HERMES_WEBUI_ALLOWED_ORIGINS", value = "https://${local.hostname}" },
                  { name = "HERMES_WEBUI_AGENT_CACHE_MAX", value = "3" }, { name = "HERMES_WEBUI_SESSIONS_MAX", value = "25" }
                ]
                resources    = { requests = { cpu = "250m", memory = "512Mi" }, limits = { cpu = "1", memory = "2Gi" } }
                volumeMounts = [{ name = "home", mountPath = "/home/hermeswebui/.hermes" }, { name = "agent-source", mountPath = "/home/hermeswebui/.hermes/hermes-agent", readOnly = true }, { name = "workspace", mountPath = "/workspace" }]
              }
            ]
            volumes = [
              { name = "home", persistentVolumeClaim = { claimName = "hermes-home" } },
              { name = "agent-source", emptyDir = {} }, { name = "workspace", emptyDir = {} }
            ]
          }
        }
      }
    })
    service = yamlencode({ apiVersion = "v1", kind = "Service", metadata = { name = "hermes-webui", namespace = var.namespace, labels = local.labels }, spec = { selector = { app = "hermes" }, ports = [{ name = "http", port = 8787, targetPort = "http" }] } })
    route   = yamlencode({ apiVersion = "traefik.io/v1alpha1", kind = "IngressRoute", metadata = { name = "hermes", namespace = var.namespace, labels = local.labels }, spec = { entryPoints = ["websecure"], routes = [{ kind = "Rule", match = "Host(`${local.hostname}`)", middlewares = [{ name = "authentik" }], services = [{ name = "hermes-webui", port = 8787 }] }], tls = {} } })
  }
}

resource "kubectl_manifest" "this" {
  for_each          = local.manifests
  yaml_body         = each.value
  server_side_apply = true
  field_manager     = "terraform-hermes"
  wait_for_rollout  = each.key == "source-init"
}

output "url" { value = "https://${local.hostname}" }
