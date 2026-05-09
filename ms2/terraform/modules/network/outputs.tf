output "network_self_link" {
  description = "VPC network self link."
  value       = google_compute_network.vpc.self_link
}

output "subnet_self_link" {
  description = "Subnet self link."
  value       = google_compute_subnetwork.primary.self_link
}

output "pods_secondary_range_name" {
  description = "Secondary range name for GKE pods."
  value       = var.pods_secondary_range.name
}

output "services_secondary_range_name" {
  description = "Secondary range name for GKE services."
  value       = var.services_secondary_range.name
}
