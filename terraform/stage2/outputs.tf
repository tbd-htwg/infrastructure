output "project_id" {
  description = "GCP project id."
  value       = var.project_id
}

output "region" {
  description = "Region used for regional resources."
  value       = var.region
}

output "cloudsql_connection_name" {
  description = "Instance connection name (project:region:instance)."
  value       = google_sql_database_instance.main.connection_name
}

output "run_service_account_email" {
  description = "Cloud Run runtime service account email."
  value       = google_service_account.cloud_run.email
}

output "db_name" {
  description = "Database name inside Cloud SQL."
  value       = var.db_name
}

output "db_user" {
  description = "PostgreSQL application user."
  value       = var.db_user
}

output "db_password_secret_id" {
  description = "Secret Manager secret id for SPRING_DATASOURCE_PASSWORD."
  value       = google_secret_manager_secret.db_password.secret_id
}

output "frontend_bucket_name" {
  description = "GCS bucket (created by stage 1) serving the React SPA."
  value       = data.google_storage_bucket.frontend.name
}

output "frontend_lb_ip" {
  description = "Global IP for the HTTPS load balancer. Both SPA and API hostnames are A records to this address."
  value       = google_compute_global_address.frontend_lb.address
}

output "frontend_url_map_name" {
  description = "URL map name (pass to gcloud compute url-maps invalidate-cdn-cache for SPA releases)."
  value       = google_compute_url_map.frontend.name
}

output "frontend_https_url" {
  description = "Public SPA URL."
  value       = "https://${var.frontend_hostname}"
}

output "cloud_run_api_url" {
  description = "Public API URL (routed via HTTPS LB to Cloud Run)."
  value       = "https://${var.cloud_run_api_hostname}"
}

output "cloud_run_backend_service_uri" {
  description = "Direct Cloud Run HTTPS URL (googleapis.com host); the LB route at cloud_run_api_url is the public API."
  value       = google_cloud_run_v2_service.backend.uri
}

output "cloud_run_backend_service_name" {
  description = "Cloud Run API service name; also the Docker image name under artifact_repo."
  value       = google_cloud_run_v2_service.backend.name
}

output "vite_api_base_url" {
  description = "Spring Data REST base URL for the Vite build (https://cloud_run_api_hostname/api/v2)."
  value       = "https://${var.cloud_run_api_hostname}/api/v2"
}

output "dns_managed_zone_name" {
  description = "Existing Cloud DNS managed zone used when manage_cloud_dns_records is true."
  value       = var.manage_cloud_dns_records ? var.dns_managed_zone_name : null
}

output "dns_traffic_routing" {
  description = "DNS hint: SPA and API are both A records to the same HTTPS LB IP; host-based routing inside the LB dispatches to GCS (SPA) or Cloud Run (API)."
  value       = <<-EOT
    SPA (${var.frontend_hostname}): A → ${google_compute_global_address.frontend_lb.address} (HTTPS LB → GCS bucket).
    API (${var.cloud_run_api_hostname}): A → ${google_compute_global_address.frontend_lb.address} (HTTPS LB → Cloud Run via serverless NEG).
  EOT
}

output "cloud_armor_policy_name" {
  description = "Cloud Armor security policy name attached to the API backend service (null when enable_cloud_armor is false)."
  value       = var.enable_cloud_armor ? google_compute_security_policy.api[0].name : null
}
