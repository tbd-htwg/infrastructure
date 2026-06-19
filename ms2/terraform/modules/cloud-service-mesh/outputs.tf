output "membership_id" {
  description = "Fleet membership ID."
  value       = google_gke_hub_membership.cluster.membership_id
}

output "membership_name" {
  description = "Fully qualified fleet membership name."
  value       = google_gke_hub_membership.cluster.name
}

output "feature_id" {
  description = "Cloud Service Mesh fleet feature ID."
  value       = google_gke_hub_feature.service_mesh.id
}

output "feature_membership_id" {
  description = "Per-cluster Cloud Service Mesh feature membership ID."
  value       = google_gke_hub_feature_membership.service_mesh.id
}
