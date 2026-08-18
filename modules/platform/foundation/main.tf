locals {
  gateway_api_url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_version}/standard-install.yaml"
}

data "http" "gateway_api" {
  url = local.gateway_api_url

  request_headers = {
    Accept = "application/yaml"
  }
}

data "kubectl_file_documents" "gateway_api" {
  content = data.http.gateway_api.response_body
}

resource "kubernetes_namespace_v1" "this" {
  for_each = var.namespaces

  metadata {
    name   = each.key
    labels = each.value
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubectl_manifest" "gateway_api_crd" {
  for_each = data.kubectl_file_documents.gateway_api.manifests

  yaml_body         = each.value
  server_side_apply = true
  field_manager     = "terraform-gateway-api"
  force_conflicts   = false
  apply_only        = true
  wait              = true

  lifecycle {
    precondition {
      condition     = sha256(data.http.gateway_api.response_body) == var.gateway_api_sha256
      error_message = "Gateway API release asset checksum mismatch; review the upstream artifact before changing the expected digest."
    }
  }

  depends_on = [kubernetes_namespace_v1.this]
}
