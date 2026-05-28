output "service_account_emails" {
  description = "Service account emails for integrations."
  value       = module.project_bootstrap.service_account_emails
}

output "secrets_deployer_sa_email" {
  description = "GitHub Actions service account email for Secret Manager syncs."
  value       = module.project_bootstrap.service_account_emails["secrets_deployer"]
}

output "artifact_registry_repo" {
  description = "Artifact Registry repository name."
  value       = module.project_bootstrap.artifact_registry_repo
}

output "dns_zone_name" {
  description = "Cloud DNS managed zone name."
  value       = module.project_bootstrap.dns_zone_name
}

output "log_sink_bucket" {
  description = "Log sink bucket name."
  value       = module.project_bootstrap.log_sink_bucket
}

output "network_self_link" {
  description = "VPC network self link."
  value       = module.network.network_self_link
}

output "subnet_self_link" {
  description = "Subnet self link."
  value       = module.network.subnet_self_link
}

output "gke_cluster_name" {
  description = "GKE Autopilot cluster name."
  value       = module.gke_autopilot.cluster_name
}

output "gke_cluster_location" {
  description = "GKE Autopilot cluster location."
  value       = module.gke_autopilot.cluster_location
}


output "storage_buckets" {
  description = "Storage bucket names."
  value       = module.storage.bucket_names
}

output "frontend_domain" {
  description = "Frontend domain."
  value       = module.frontend_lb.frontend_domain
}

output "github_wif_provider" {
  description = "WIF provider name for GitHub Actions."
  value       = module.github_wif.workload_identity_provider
}

output "backend_wif_provider" {
  description = "WIF provider name for backend GitHub Actions."
  value       = google_iam_workload_identity_pool_provider.backend.name
}

output "frontend_deployer_sa" {
  description = "Frontend deployer service account email."
  value       = module.github_wif.deployer_service_account
}

output "frontend_ip" {
  description = "Frontend global IP address."
  value       = module.frontend_lb.frontend_ip
}
