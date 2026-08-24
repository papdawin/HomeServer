locals {
  immich_url    = "https://immich.${var.domain}"
  authentik_url = "https://auth.${var.domain}"
  configuration = yamlencode({
    oauth = {
      enabled                 = true
      autoLaunch              = false
      autoRegister            = true
      buttonText              = "Login with Authentik"
      clientId                = var.oidc_client_id
      clientSecret            = var.oidc_client_secret
      issuerUrl               = "${local.authentik_url}/application/o/immich/"
      scope                   = "openid email profile"
      signingAlgorithm        = "RS256"
      profileSigningAlgorithm = "none"
      tokenEndpointAuthMethod = "client_secret_post"
      mobileOverrideEnabled   = false
      mobileRedirectUri       = ""
    }
    passwordLogin = {
      enabled = true
    }
    server = {
      externalDomain = local.immich_url
    }
    newVersionCheck = {
      enabled = false
    }
  })
}

resource "kubernetes_secret_v1" "configuration" {
  metadata {
    name      = "immich-configuration"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "immich"
    }
  }

  data_wo = {
    "immich-config.yaml" = local.configuration
  }
  data_wo_revision = var.secret_revision
  type             = "Opaque"
}

resource "helm_release" "immich" {
  name      = "immich"
  namespace = var.namespace
  # Vendored because this chart's remote JSON-schema reference breaks the
  # Helm provider's dry-run validation. Chart version remains pinned here.
  chart = "${path.module}/charts/immich"

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  wait_for_jobs   = true
  timeout         = 1200
  # The published chart schema references an HTTPS schema that Helm's lint
  # library cannot load. Template rendering is validated separately.
  lint        = false
  max_history = 5

  values = [yamlencode({
    controllers = {
      main = {
        pod = {
          automountServiceAccountToken = false
          securityContext = {
            runAsNonRoot = true
            runAsUser    = 1000
            runAsGroup   = 1000
            fsGroup      = 1000
            seccompProfile = {
              type = "RuntimeDefault"
            }
          }
        }
        containers = {
          main = {
            image = {
              tag = var.image_version
            }
            securityContext = {
              allowPrivilegeEscalation = false
              capabilities = {
                drop = ["ALL"]
              }
            }
          }
        }
      }
    }
    immich = {
      metrics = {
        enabled = false
      }
      persistence = {
        library = {
          existingClaim = "immich-library"
        }
      }
      configurationKind     = "Secret"
      existingConfiguration = kubernetes_secret_v1.configuration.metadata[0].name
    }
    valkey = {
      enabled = true
      controllers = {
        main = {
          containers = {
            main = {
              resources = {
                requests = {
                  cpu    = "25m"
                  memory = "64Mi"
                }
                limits = {
                  cpu    = "500m"
                  memory = "256Mi"
                }
              }
              securityContext = {
                allowPrivilegeEscalation = false
                capabilities = {
                  drop = ["ALL"]
                }
              }
            }
          }
        }
      }
      persistence = {
        data = {
          enabled = true
          type    = "emptyDir"
        }
      }
    }
    server = {
      enabled = true
      controllers = {
        main = {
          containers = {
            main = {
              env = {
                DB_HOSTNAME      = "immich-postgres-rw"
                DB_PORT          = "5432"
                DB_DATABASE_NAME = "immich"
                DB_USERNAME = {
                  valueFrom = {
                    secretKeyRef = {
                      name = "immich-postgres-credentials"
                      key  = "username"
                    }
                  }
                }
                DB_PASSWORD = {
                  valueFrom = {
                    secretKeyRef = {
                      name = "immich-postgres-credentials"
                      key  = "password"
                    }
                  }
                }
              }
              resources = {
                requests = {
                  cpu    = "250m"
                  memory = "512Mi"
                }
                limits = {
                  cpu    = "2"
                  memory = "2Gi"
                }
              }
            }
          }
        }
      }
      ingress = {
        main = {
          enabled = false
        }
      }
    }
    # Keep explicit so a chart update cannot re-enable this resource-heavy component.
    "machine-learning" = { enabled = false }
  })]

  lifecycle {
    precondition {
      condition     = !can(regex("(?i)(change|replace|placeholder)", var.oidc_client_secret))
      error_message = "Immich OIDC secret is still a placeholder."
    }
  }
}

resource "kubectl_manifest" "route" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "immich"
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
      hostnames = ["immich.${var.domain}"]
      rules = [{
        matches = [{
          path = {
            type  = "PathPrefix"
            value = "/"
          }
        }]
        backendRefs = [{
          name = "immich-server"
          port = 2283
        }]
      }]
    }
  })

  server_side_apply = true
  field_manager     = "terraform-immich"
  depends_on        = [helm_release.immich]
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
      ingress     = [{ from = [{ podSelector = {} }] }]
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
        ports = [{ protocol = "TCP", port = 2283 }]
      }]
    }
    cnpg-operator = {
      podSelector = { matchLabels = { "cnpg.io/cluster" = "immich-postgres" } }
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
  field_manager     = "terraform-immich"
}

output "url" {
  value = local.immich_url
}
