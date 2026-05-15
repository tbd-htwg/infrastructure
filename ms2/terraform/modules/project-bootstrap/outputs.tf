output "service_account_emails" {
  description = "Created service account emails."
  value       = { for key, sa in google_service_account.service_accounts : key => sa.email }
}

output "artifact_registry_repo" {
  description = "Artifact Registry repository name."
  value       = var.artifact_registry_enabled ? google_artifact_registry_repository.repo[0].name : null
}

output "dns_zone_name" {
  description = "Cloud DNS managed zone name."
  value       = var.enable_dns ? google_dns_managed_zone.zone[0].name : null
}

output "dns_zone_name_servers" {
  description = "Cloud DNS name servers for the managed zone (registrar NS or parent delegation)."
  value       = var.enable_dns ? google_dns_managed_zone.zone[0].name_servers : []
}

output "log_sink_bucket" {
  description = "Log sink bucket name."
  value       = var.log_sink.enabled ? google_storage_bucket.log_sink[0].name : null
}
