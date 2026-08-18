resource "kubernetes_service_account_v1" "authentik" {
  metadata {
    name      = "authentik-workloads"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  automount_service_account_token = false
}

resource "helm_release" "authentik" {
  name       = "authentik"
  namespace  = var.namespace
  repository = "https://charts.goauthentik.io"
  chart      = "authentik"
  version    = var.chart_version

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  wait_for_jobs   = true
  max_history     = 5
  timeout         = 900
  lint            = true

  values = [yamlencode({
    global = {
      env = [
        { name = "AUTHENTIK_HOST", value = "https://auth.${var.domain}" },
        { name = "AUTHENTIK_HOST_BROWSER", value = "https://auth.${var.domain}" }
      ]
      volumeMounts = [{

        name      = "media"
        mountPath = "/media"
      }]
      volumes = [{
        name = "media"
        persistentVolumeClaim = {
          claimName = "authentik-media"
        }
      }]
    }
    authentik = {
      env = [
        { name = "AUTHENTIK_HOST", value = "https://auth.${var.domain}" },
        { name = "AUTHENTIK_HOST_BROWSER", value = "https://auth.${var.domain}" }
      ]
      existingSecret = {
        secretName = "authentik-secrets"
      }
    }
    server = {
      replicas                     = 1
      serviceAccountName           = kubernetes_service_account_v1.authentik.metadata[0].name
      automountServiceAccountToken = false
      nodeSelector = {
        "kubernetes.io/hostname" = "talos2"
      }
      ingress = {
        enabled = false
      }
      route = {
        main = {
          enabled = false
        }
      }
      metrics = {
        enabled = false
        serviceMonitor = {
          enabled = false
        }
      }
      securityContext = {
        runAsNonRoot = true
        runAsUser    = 1000
        runAsGroup   = 1000
        fsGroup      = 1000
        seccompProfile = {
          type = "RuntimeDefault"
        }
      }
      containerSecurityContext = {
        allowPrivilegeEscalation = false
        capabilities = {
          drop = ["ALL"]
        }
        seccompProfile = {
          type = "RuntimeDefault"
        }
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }
    }
    worker = {
      replicas                     = 1
      serviceAccountName           = kubernetes_service_account_v1.authentik.metadata[0].name
      automountServiceAccountToken = false
      metrics = {
        enabled = false
        serviceMonitor = {
          enabled = false
        }
      }
      securityContext = {
        runAsNonRoot = true
        runAsUser    = 1000
        runAsGroup   = 1000
        fsGroup      = 1000
        seccompProfile = {
          type = "RuntimeDefault"
        }
      }
      containerSecurityContext = {
        allowPrivilegeEscalation = false
        capabilities = {
          drop = ["ALL"]
        }
        seccompProfile = {
          type = "RuntimeDefault"
        }
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }
    }
    serviceAccount = {
      create = false
    }
    geoip = {
      enabled = false
    }
    prometheus = {
      rules = {
        enabled = false
      }
    }
    postgresql = {
      enabled = false
    }
  })]

  depends_on = [kubernetes_service_account_v1.authentik]
}

resource "kubectl_manifest" "route" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "authentik"
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }
    spec = {
      parentRefs = [{
        name        = "internal-gateway"
        namespace   = "traefik"
        sectionName = "https"
      }]
      hostnames = ["auth.${var.domain}"]
      rules = [{
        matches = [{
          path = {
            type  = "PathPrefix"
            value = "/"
          }
        }]
        backendRefs = [{
          name = "authentik-server"
          port = 80
        }]
      }]
    }
  })

  server_side_apply = true
  field_manager     = "terraform-authentik"
  depends_on        = [helm_release.authentik]
}

locals {
  network_policies = {
    default-deny = {
      podSelector = {}
      policyTypes = ["Ingress"]
    }
    same-namespace = {
      podSelector = {}
      policyTypes = ["Ingress"]
      ingress = [{
        from = [{ podSelector = {} }]
      }]
    }
    traefik = {
      podSelector = {}
      policyTypes = ["Ingress"]
      ingress = [{
        from = [{
          namespaceSelector = {
            matchLabels = { "kubernetes.io/metadata.name" = "traefik" }
          }
          podSelector = {
            matchLabels = { "app.kubernetes.io/name" = "traefik" }
          }
        }]
        ports = [{ protocol = "TCP", port = 9000 }]
      }]
    }
    cnpg-operator = {
      podSelector = { matchLabels = { "cnpg.io/cluster" = "authentik-postgres" } }
      policyTypes = ["Ingress"]
      ingress = [{
        from = [{
          namespaceSelector = {
            matchLabels = { "kubernetes.io/metadata.name" = "cnpg-system" }
          }
          podSelector = {
            matchLabels = { "app.kubernetes.io/name" = "cloudnative-pg" }
          }
        }]
        ports = [{ protocol = "TCP", port = 8000 }]
      }]
    }
  }
}

resource "kubectl_manifest" "network_policy" {
  for_each = local.network_policies

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = each.key
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }
    spec = each.value
  })

  server_side_apply = true
  field_manager     = "terraform-authentik"
}

output "url" {
  value = "https://auth.${var.domain}"
}
