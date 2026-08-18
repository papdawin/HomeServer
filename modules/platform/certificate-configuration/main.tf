locals {
  token_is_placeholder = can(regex("(?i)(change|replace|placeholder)", var.cloudflare_api_token))
  issuers = {
    letsencrypt-staging    = "https://acme-staging-v02.api.letsencrypt.org/directory"
    letsencrypt-production = "https://acme-v02.api.letsencrypt.org/directory"
  }
}

resource "kubernetes_secret_v1" "cloudflare" {
  metadata {
    name      = "cloudflare-api-token"
    namespace = "cert-manager"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data_wo = {
    api-token = var.cloudflare_api_token
  }
  data_wo_revision = var.secret_revision
  type             = "Opaque"

  lifecycle {
    precondition {
      condition     = !local.token_is_placeholder && length(var.cloudflare_api_token) >= 20
      error_message = "The Cloudflare SOPS file still contains a placeholder or invalid token."
    }
  }
}

resource "kubectl_manifest" "issuer" {
  for_each = local.issuers

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = each.key
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }
    spec = {
      acme = {
        email  = var.acme_email
        server = each.value
        privateKeySecretRef = {
          name = "${each.key}-account-key"
        }
        solvers = [{
          selector = {
            dnsZones = [var.dns_zone]
          }
          dns01 = {
            cloudflare = {
              apiTokenSecretRef = {
                name = kubernetes_secret_v1.cloudflare.metadata[0].name
                key  = "api-token"
              }
            }
          }
        }]
      }
    }
  })

  server_side_apply = true
  field_manager     = "terraform-cert-manager"
  depends_on        = [kubernetes_secret_v1.cloudflare]
}

resource "kubectl_manifest" "wildcard_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "home-papdavid-eu"
      namespace = "traefik"
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }
    spec = {
      secretName = "home-papdavid-eu-tls"
      commonName = "*.${var.domain}"
      dnsNames   = ["*.${var.domain}"]
      issuerRef = {
        kind = "ClusterIssuer"
        name = var.certificate_issuer_name
      }
      privateKey = {
        algorithm = "ECDSA"
        size      = 256
      }
    }
  })

  server_side_apply = true
  field_manager     = "terraform-cert-manager"
  depends_on        = [kubectl_manifest.issuer]
}

output "certificate_issuer" {
  value = var.certificate_issuer_name
}
