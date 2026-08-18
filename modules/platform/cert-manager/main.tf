resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  namespace  = var.namespace
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.chart_version

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  wait_for_jobs   = true
  max_history     = 5
  timeout         = 600
  lint            = true

  values = [yamlencode({
    crds = {
      enabled = true
      keep    = true
    }
    prometheus = {
      enabled = false
    }
    resources = {
      requests = {
        cpu    = "50m"
        memory = "128Mi"
      }
      limits = {
        cpu    = "500m"
        memory = "512Mi"
      }
    }
    webhook = {
      resources = {
        requests = {
          cpu    = "20m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "128Mi"
        }
      }
    }
    cainjector = {
      resources = {
        requests = {
          cpu    = "20m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }
    }
    startupapicheck = {
      resources = {
        requests = {
          cpu    = "10m"
          memory = "32Mi"
        }
        limits = {
          cpu    = "100m"
          memory = "64Mi"
        }
      }
    }
  })]
}

output "release_name" {
  value = helm_release.cert_manager.name
}
