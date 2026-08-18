output "gateway_name" {
  value = "internal-gateway"
}

output "node_ports" {
  value = {
    http  = 80
    https = 443
  }
}
