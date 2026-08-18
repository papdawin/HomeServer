locals {
  truenas_manifest_url      = "https://raw.githubusercontent.com/truenas/truenas-csi/${var.truenas_csi_commit}/deploy/truenas-csi-driver.yaml"
  truenas_node_document_key = "/apis/apps/v1/namespaces/truenas-csi/daemonsets/truenas-csi-node"
  excluded_truenas_documents = [
    "Namespace/truenas-csi",
    "Secret/truenas-api-credentials",
    "ConfigMap/truenas-csi-config",
  ]
}

data "http" "truenas_csi" {
  url = local.truenas_manifest_url
}

data "kubectl_file_documents" "truenas_csi" {
  content = replace(
    data.http.truenas_csi.response_body,
    "ghcr.io/truenas/truenas-csi:latest",
    "ghcr.io/truenas/truenas-csi:${var.truenas_csi_version}",
  )
}

data "kubectl_file_documents" "local_path" {
  content = templatefile("${path.module}/manifests/local-path.yaml.tftpl", {
    image_version      = var.local_path_version
    worker_node        = var.worker_node
    control_plane_node = var.control_plane_node
  })
}

data "kubectl_file_documents" "static_volumes" {
  content = templatefile("${path.module}/manifests/static-volumes.yaml.tftpl", {
    truenas_address = var.truenas_address
  })
}

locals {
  truenas_documents = {
    for key, document in data.kubectl_file_documents.truenas_csi.manifests : key => document
    if !contains(
      local.excluded_truenas_documents,
      "${try(yamldecode(document).kind, "")}/${try(yamldecode(document).metadata.name, "")}",
    )
  }
  truenas_base_documents = {
    for key, document in local.truenas_documents : key => document
    if !contains(["Deployment", "DaemonSet", "StatefulSet"], try(yamldecode(document).kind, ""))
  }
  truenas_workload_documents = {
    for key, document in local.truenas_documents : key => key == local.truenas_node_document_key ? templatefile(
      "${path.module}/manifests/truenas-csi-node-nfs.yaml.tftpl",
      { image_version = var.truenas_csi_version },
    ) : document
    if contains(["Deployment", "DaemonSet", "StatefulSet"], try(yamldecode(document).kind, ""))
  }
  local_path_base_documents = {
    for key, document in data.kubectl_file_documents.local_path.manifests : key => document
    if try(yamldecode(document).kind, "") != "Deployment"
  }
  local_path_workload_documents = {
    for key, document in data.kubectl_file_documents.local_path.manifests : key => document
    if try(yamldecode(document).kind, "") == "Deployment"
  }
  truenas_key_placeholder = can(regex("(?i)(change|replace|placeholder|your-api-key)", var.truenas_api_key))
}

resource "kubernetes_secret_v1" "truenas" {
  metadata {
    name      = "truenas-api-credentials"
    namespace = "truenas-csi"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data_wo = {
    api-key = var.truenas_api_key
  }
  data_wo_revision = var.secret_revision
  type             = "Opaque"

  lifecycle {
    precondition {
      condition     = var.truenas_credential_rotated
      error_message = "Refusing to use the TrueNAS API key exposed in chat. Revoke it, update the SOPS file, then set truenas_credential_rotated to true."
    }
    precondition {
      condition     = !local.truenas_key_placeholder && length(var.truenas_api_key) >= 20
      error_message = "The TrueNAS SOPS file contains a placeholder or invalid key."
    }
  }
}

resource "kubernetes_config_map_v1" "truenas" {
  metadata {
    name      = "truenas-csi-config"
    namespace = "truenas-csi"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    truenasURL      = "wss://${var.truenas_address}/api/current"
    truenasInsecure = "true"
    defaultPool     = var.truenas_pool
    nfsServer       = var.truenas_address
    iscsiPortal     = "${var.truenas_address}:3260"
    nvmeofPortal    = "${var.truenas_address}:4420"
    iscsiIQNBase    = "iqn.2005-10.org.freenas.ctl"
  }
}

resource "kubectl_manifest" "local_path_base" {
  for_each = local.local_path_base_documents

  yaml_body         = each.value
  server_side_apply = true
  field_manager     = "terraform-local-path"
}

resource "kubectl_manifest" "local_path_workload" {
  for_each = local.local_path_workload_documents

  yaml_body         = each.value
  server_side_apply = true
  field_manager     = "terraform-local-path"
  wait_for_rollout  = true
  depends_on        = [kubectl_manifest.local_path_base]
}

resource "kubectl_manifest" "truenas_base" {
  for_each = local.truenas_base_documents

  yaml_body         = each.value
  server_side_apply = true
  field_manager     = "terraform-truenas-csi"

  lifecycle {
    precondition {
      condition     = sha256(data.http.truenas_csi.response_body) == var.truenas_csi_sha256
      error_message = "TrueNAS CSI manifest checksum mismatch; review upstream before updating the expected digest."
    }
  }

  depends_on = [kubernetes_secret_v1.truenas, kubernetes_config_map_v1.truenas]
}

resource "kubectl_manifest" "truenas_workload" {
  for_each = local.truenas_workload_documents

  yaml_body         = each.value
  server_side_apply = true
  field_manager     = "terraform-truenas-csi"
  wait_for_rollout  = true

  lifecycle {
    precondition {
      condition     = sha256(data.http.truenas_csi.response_body) == var.truenas_csi_sha256
      error_message = "TrueNAS CSI manifest checksum mismatch; review upstream before updating the expected digest."
    }
    precondition {
      condition     = contains(keys(local.truenas_documents), local.truenas_node_document_key)
      error_message = "The pinned TrueNAS CSI manifest no longer contains the expected node DaemonSet; review the NFS-only override."
    }
  }

  depends_on = [kubectl_manifest.truenas_base]
}

resource "kubectl_manifest" "truenas_storage_class" {
  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "truenas-nfs"
      annotations = {
        "storageclass.kubernetes.io/is-default-class" = "false"
      }
    }
    provisioner = "csi.truenas.io"
    parameters = {
      protocol           = "nfs"
      pool               = var.truenas_pool
      datasetPath        = "kubernetes/dynamic"
      compression        = "LZ4"
      sync               = "STANDARD"
      "nfs.mountOptions" = "hard,nfsvers=4.1,noatime"
      "nfs.hosts"        = "${var.worker_address},${var.control_plane_address}"
    }
    reclaimPolicy        = "Retain"
    volumeBindingMode    = "Immediate"
    allowVolumeExpansion = true
  })

  server_side_apply = true
  field_manager     = "terraform-storage"
  depends_on        = [kubectl_manifest.truenas_base]
}

resource "kubernetes_namespace_v1" "arr" {
  metadata {
    name = "arr"
    labels = {
      "gateway-access"                       = "internal"
      "pod-security.kubernetes.io/enforce"   = "baseline"
    }
  }
}

resource "kubectl_manifest" "static_volume" {
  for_each = data.kubectl_file_documents.static_volumes.manifests

  yaml_body         = each.value
  server_side_apply = true
  field_manager     = "terraform-static-storage"
  apply_only        = true
}

output "storage_classes" {
  value = ["local-ssd", "truenas-nfs"]
}
