output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.autopilot.name
}

output "cluster_location" {
  description = "GKE cluster location."
  value       = google_container_cluster.autopilot.location
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint."
  value       = google_container_cluster.autopilot.endpoint
}
