output "frontend_ip" {
  description = "Frontend global IP address."
  value       = google_compute_global_address.frontend_ip.address
}

output "frontend_domain" {
  description = "Frontend domain."
  value       = var.frontend_domain
}

output "api_backend_service" {
  description = "API backend service self link (if enabled)."
  value       = local.has_api_backend ? google_compute_backend_service.api[0].self_link : null
}
