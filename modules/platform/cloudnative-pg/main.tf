resource "helm_release" "cloudnative_pg" {
  name       = "cloudnative-pg"
  namespace  = var.namespace
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
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
      create = true
    }
    monitoring = {
      podMonitorEnabled = false
      grafanaDashboard = {
        create = false
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

output "operator_release" {
  value = helm_release.cloudnative_pg.name
}
