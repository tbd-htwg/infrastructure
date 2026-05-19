output "frontend_ip" {
  description = "Frontend global IP address."
  value       = google_compute_global_address.frontend_ip.address
}

output "frontend_domain" {
  description = "Frontend domain."
  value       = var.frontend_domain
}
