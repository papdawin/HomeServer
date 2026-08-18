locals {
  contains_placeholder = anytrue([
    for value in values(var.secret_data) : can(regex("(?i)(change|replace|placeholder)", value))
  ])
  cluster_spec = merge({
    instances             = 1
    primaryUpdateStrategy = "unsupervised"
    imageName = var.postgresql_image
    }, {
      bootstrap = {
        initdb = {
        database = var.database_name
        owner    = var.database_owner
        secret = {
          name = var.credentials_secret_name
        }
        encoding = "UTF8"
      }
    }
    storage = {
      storageClass = "local-ssd"
      size         = var.storage_size
    }
    affinity = {
      nodeSelector = {
        "kubernetes.io/hostname" = var.node_name
      }
    }
    resources = var.resources
    monitoring = {
      enablePodMonitor = false
    }
    }, var.enable_immich_extensions ? {
    postgresql = {
      shared_preload_libraries = ["vchord.so"]
      extensions = [{
        name                   = "vchord"
        dynamic_library_path   = ["/usr/lib/postgresql/18/lib"]
        extension_control_path = ["/usr/share/postgresql/18/"]
        image = {
          reference = var.vectorchord_image
        }
      }]
    }
  } : {})
  backup_command = <<-SCRIPT
    output="/backup/${var.database_name}-$(date -u +%Y%m%dT%H%M%SZ).dump"
    partial="$output.partial"
    trap 'rm -f "$partial"' EXIT
    pg_dump --format=custom --compress=6 --file="$partial"
    mv "$partial" "$output"
    find /backup -maxdepth 1 -type f -name '${var.database_name}-*.dump' -mtime +2 -delete
  SCRIPT
}

resource "kubernetes_secret_v1" "credentials" {
  metadata {
    name      = var.credentials_secret_name
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = var.database_name
    }
  }

  data_wo          = var.secret_data
  data_wo_revision = var.secret_revision
  type             = "Opaque"

  lifecycle {
    precondition {
      condition     = !local.contains_placeholder
      error_message = "The SOPS credentials for ${var.database_name} still contain a placeholder."
    }
  }
}

resource "kubectl_manifest" "cluster" {
  yaml_body = yamlencode({
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name      = var.cluster_name
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/part-of"    = var.database_name
      }
    }
    spec = local.cluster_spec
  })

  server_side_apply = true
  field_manager     = "terraform-cloudnative-pg"

  wait_for {
    condition {
      type   = "Ready"
      status = "True"
    }
  }

  timeouts {
    create = "20m"
    update = "20m"
    delete = "10m"
  }

  depends_on = [kubernetes_secret_v1.credentials]
}

resource "kubectl_manifest" "database" {
  count = var.enable_immich_extensions ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Database"
    metadata = {
      name      = var.database_name
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }
    spec = {
      name                  = var.database_name
      owner                 = var.database_owner
      databaseReclaimPolicy = "retain"
      cluster = {
        name = var.cluster_name
      }
      extensions = [
        { name = "vector", ensure = "present" },
        { name = "vchord", ensure = "present" },
        { name = "earthdistance", ensure = "present" },
        { name = "cube", ensure = "present" },
      ]
    }
  })

  server_side_apply = true
  field_manager     = "terraform-cloudnative-pg"
  depends_on        = [kubectl_manifest.cluster]
}

resource "kubectl_manifest" "backup" {
  yaml_body = yamlencode({
    apiVersion = "batch/v1"
    kind       = "CronJob"
    metadata = {
      name      = "${var.cluster_name}-backup"
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/part-of"    = var.database_name
      }
    }
    spec = {
      schedule                   = var.backup_schedule
      timeZone                   = "Europe/Budapest"
      concurrencyPolicy          = "Forbid"
      successfulJobsHistoryLimit = 1
      failedJobsHistoryLimit     = 2
      jobTemplate = {
        spec = {
          backoffLimit            = 2
          ttlSecondsAfterFinished = 86400
          template = {
            metadata = {
              labels = {
                "app.kubernetes.io/name" = "${var.cluster_name}-backup"
              }
            }
            spec = {
              restartPolicy                = "Never"
              automountServiceAccountToken = false
              securityContext = {
                runAsNonRoot = true
                runAsUser    = 26
                runAsGroup   = 26
                fsGroup      = 26
                seccompProfile = {
                  type = "RuntimeDefault"
                }
              }
              containers = [{
                name            = "pg-dump"
                image           = var.postgresql_image
                imagePullPolicy = "IfNotPresent"
                securityContext = {
                  allowPrivilegeEscalation = false
                  readOnlyRootFilesystem   = true
                  capabilities = {
                    drop = ["ALL"]
                  }
                }
                resources = {
                  requests = {
                    cpu    = "100m"
                    memory = "128Mi"
                  }
                  limits = {
                    cpu    = "1"
                    memory = "512Mi"
                  }
                }
                env = [
                  { name = "PGHOST", value = "${var.cluster_name}-rw" },
                  { name = "PGDATABASE", value = var.database_name },
                  {
                    name = "PGUSER"
                    valueFrom = {
                      secretKeyRef = {
                        name = var.credentials_secret_name
                        key  = "username"
                      }
                    }
                  },
                  {
                    name = "PGPASSWORD"
                    valueFrom = {
                      secretKeyRef = {
                        name = var.credentials_secret_name
                        key  = "password"
                      }
                    }
                  },
                ]
                command = ["/bin/sh", "-ec", local.backup_command]
                volumeMounts = [{
                  name      = "backups"
                  mountPath = "/backup"
                }]
              }]
              volumes = [{
                name = "backups"
                persistentVolumeClaim = {
                  claimName = var.backup_pvc_name
                }
              }]
            }
          }
        }
      }
    }
  })

  server_side_apply = true
  field_manager     = "terraform-postgres-backup"
  depends_on        = [kubectl_manifest.cluster]
}

output "cluster_name" {
  value = var.cluster_name
}

output "read_write_service" {
  value = "${var.cluster_name}-rw"
}
