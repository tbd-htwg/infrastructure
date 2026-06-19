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

output "cluster_id" {
  description = "Fully qualified GKE cluster resource ID."
  value       = google_container_cluster.autopilot.id
}
