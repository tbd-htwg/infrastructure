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

output "cloudsql_connection_name" {
  description = "Cloud SQL instance connection name."
  value       = module.cloudsql.instance_connection_name
}

output "cloudsql_shared_db" {
  description = "Shared database name for free tier."
  value       = module.cloudsql.shared_database_name
}

output "cloudsql_tenant_dbs" {
  description = "Tenant database names."
  value       = module.cloudsql.tenant_database_names
}

output "storage_buckets" {
  description = "Storage bucket names."
  value       = module.storage.bucket_names
}

output "parent_dns_zone_name_servers" {
  description = "Registrar nameservers when enable_parent_dns_zone is true (public DNS for tbd-htwg.de)."
  value       = var.enable_parent_dns_zone ? google_dns_managed_zone.parent[0].name_servers : null
}

output "k8s_subdomain_dns_zone_name_servers" {
  description = "Nameservers for k8s.tbd-htwg.de child zone (delegated from parent when parent zone is enabled)."
  value       = module.project_bootstrap.dns_zone_name_servers
}
