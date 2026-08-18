locals {
  labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "homelab-platform"
  }
}

resource "helm_release" "traefik" {
  name       = "traefik"
  namespace  = var.namespace
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = var.chart_version

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  wait_for_jobs   = true
  max_history     = 5
  timeout         = 600
  lint            = true

  values = [yamlencode({
    deployment = {
      kind                          = "DaemonSet"
      dnsPolicy                     = "ClusterFirstWithHostNet"
      revisionHistoryLimit          = 3
      terminationGracePeriodSeconds = 30
    }
    hostNetwork = true
    updateStrategy = {
      rollingUpdate = {
        maxUnavailable = 1
        maxSurge       = 0
      }
    }
    ingressClass = {
      enabled = false
    }
    providers = {
      # Authentik forward-auth is a Traefik Middleware CRD. Gateway API does not support it as an ExtensionRef.
      kubernetesCRD = {
        enabled = true
      }
      kubernetesIngress = {
        enabled = false
      }
      kubernetesGateway = {
        enabled = true
      }
    }
    gateway = {
      enabled = false
    }
    gatewayClass = {
      enabled = false
    }
    api = {
      dashboard = false
    }
    log = {
      level = "INFO"
    }
    accessLog = {
      enabled = true
    }
    metrics = {
      addInternals = false
      prometheus   = null
    }
    service = {
      enabled = true
      spec = {
        type = "ClusterIP"
      }
    }
    ports = {
      metrics = null
      web = {
        port = 80
        expose = {
          default = true
        }
      }
      websecure = {
        port = 443
        expose = {
          default = true
        }
        http = {
          tls = {
            enabled = true
          }
        }
      }
    }
    securityContext = {
      allowPrivilegeEscalation = false
      readOnlyRootFilesystem   = true
      runAsNonRoot             = false
      runAsUser                = 0
      runAsGroup               = 0
      capabilities = {
        drop = ["ALL"]
        add  = ["NET_BIND_SERVICE"]
      }
    }
    podSecurityContext = {
      runAsNonRoot = false
      runAsUser    = 0
      runAsGroup   = 0
      seccompProfile = {
        type = "RuntimeDefault"
      }
    }
    resources = {
      requests = {
        cpu    = "100m"
        memory = "128Mi"
      }
      limits = {
        cpu    = "500m"
        memory = "384Mi"
      }
    }
  })]
}

resource "kubectl_manifest" "gateway_class" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata = {
      name   = "traefik"
      labels = local.labels
    }
    spec = {
      controllerName = "traefik.io/gateway-controller"
    }
  })

  server_side_apply = true
  field_manager     = "terraform-traefik"
  depends_on        = [helm_release.traefik]
}

resource "kubectl_manifest" "gateway" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "internal-gateway"
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      gatewayClassName = "traefik"
      listeners = [
        {
          name     = "http"
          protocol = "HTTP"
          port     = 80
          allowedRoutes = {
            namespaces = {
              from = "Selector"
              selector = {
                matchLabels = {
                  "gateway-access" = "internal"
                }
              }
            }
          }
        },
        {
          name     = "https"
          protocol = "HTTPS"
          port     = 443
          hostname = "*.${var.domain}"
          tls = {
            mode = "Terminate"
            certificateRefs = [{
              kind = "Secret"
              name = "home-papdavid-eu-tls"
            }]
          }
          allowedRoutes = {
            namespaces = {
              from = "Selector"
              selector = {
                matchLabels = {
                  "gateway-access" = "internal"
                }
              }
            }
          }
        }
      ]
    }
  })

  server_side_apply = true
  field_manager     = "terraform-traefik"
  depends_on        = [kubectl_manifest.gateway_class]
}

resource "kubectl_manifest" "https_redirect" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "redirect-http-to-https"
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      parentRefs = [{
        name        = "internal-gateway"
        sectionName = "http"
      }]
      rules = [{
        filters = [{
          type = "RequestRedirect"
          requestRedirect = {
            scheme     = "https"
            statusCode = 308
          }
        }]
      }]
    }
  })

  server_side_apply = true
  field_manager     = "terraform-traefik"
  depends_on        = [kubectl_manifest.gateway]
}
