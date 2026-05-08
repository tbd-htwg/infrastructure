output "service_account_emails" {
  description = "Service account emails for integrations."
  value       = module.project_bootstrap.service_account_emails
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
