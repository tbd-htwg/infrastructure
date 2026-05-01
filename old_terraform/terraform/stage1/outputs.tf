output "project_id" {
  description = "GCP project id (mirrors var.project_id for wrapper scripts)."
  value       = var.project_id
}

output "region" {
  description = "Region used for the Artifact Registry repo and frontend bucket."
  value       = var.region
}

output "artifact_registry_url" {
  description = "Artifact Registry base URL for docker push (region-docker.pkg.dev/project/repo)."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}

output "artifact_repo" {
  description = "Artifact Registry repository id (for stage2 data source lookup)."
  value       = google_artifact_registry_repository.docker.repository_id
}

output "frontend_bucket_name" {
  description = "GCS bucket name for the built React app. Stage 2 reads this name by convention via a data source."
  value       = google_storage_bucket.frontend.name
}
