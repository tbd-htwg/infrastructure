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

output "certificate_domains" {
  description = "Domains covered by the frontend Certificate Manager certificate."
  value       = local.certificate_domains
}

output "certificate_map_id" {
  description = "Certificate Manager map attached to the frontend HTTPS proxy."
  value       = google_certificate_manager_certificate_map.frontend.id
}
