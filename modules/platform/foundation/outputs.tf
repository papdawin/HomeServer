output "namespaces" {
  value = keys(kubernetes_namespace_v1.this)
}

output "gateway_api_version" {
  value = var.gateway_api_version
}
