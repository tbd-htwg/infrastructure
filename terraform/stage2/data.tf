# Stage 2 reads stage 1's assets via live GCP lookups (no remote-state dependency). Both stages
# share terraform.tfvars, so artifact_repo and the frontend bucket naming convention align.

data "google_artifact_registry_repository" "docker" {
  location      = var.region
  repository_id = var.artifact_repo
  project       = var.project_id
}

data "google_storage_bucket" "frontend" {
  name = coalesce(var.frontend_bucket_name, "${var.project_id}-tbd-tf-frontend-bucket")
}

data "google_dns_managed_zone" "main" {
  count   = var.manage_cloud_dns_records ? 1 : 0
  name    = var.dns_managed_zone_name
  project = var.project_id

  depends_on = [google_project_service.dns]
}
