output "tier_instance_names" {
  description = "Compute instance name per tier key."
  value       = { for k, v in google_compute_instance.tier : k => v.name }
}

output "tier_external_ips" {
  description = "Public IPv4 per tier (same as DNS when records are managed)."
  value       = { for k, v in google_compute_instance.tier : k => v.network_interface[0].access_config[0].nat_ip }
}

output "tier_hostnames" {
  description = "Intended public hostnames (<tier>-iaas.<suffix>)."
  value       = { for k in keys(local.tiers_enabled) : k => "${k}-iaas.${var.iaas_domain_suffix}" }
}

output "assets_bucket" {
  description = "GCS bucket holding docker-compose and Caddyfile for bootstrap."
  value       = google_storage_bucket.assets.name
}

output "compose_bootstrap_hint" {
  description = "Re-run or fix compose + secrets on a VM after metadata (iaas_*) is applied."
  value       = <<-EOT
    Terraform stores bucket + Secret Manager ids on each VM (metadata keys iaas_*).
    After terraform apply, either reset the instance (startup re-runs) or SSH and run:
    sudo gsutil cp gs://${google_storage_bucket.assets.name}/bootstrap-compose.sh /tmp/ && sudo bash /tmp/bootstrap-compose.sh
    Zone: ${var.zone}. Logs on the VM: /var/log/iaas-bootstrap.log
    Caddy DNS-01: the SA JSON in Secret Manager needs DNS change permission on your zone (e.g. roles/dns.admin).
  EOT
}

output "secret_env_id" {
  description = "Secret Manager secret id for the .env payload."
  value       = google_secret_manager_secret.tripplanning_env.secret_id
}

output "secret_sa_json_id" {
  description = "Secret Manager secret id for the GCP SA JSON."
  value       = google_secret_manager_secret.gcp_sa.secret_id
}

output "ghcr_token_secret_id" {
  description = "Secret Manager id for the GitHub PAT used for docker login ghcr.io (null if ghcr disabled)."
  value       = local.ghcr_enabled ? google_secret_manager_secret.ghcr_token[0].secret_id : null
}

output "vm_service_account" {
  description = "Email of the service account attached to IaaS VMs."
  value       = google_service_account.iaas_vm.email
}

output "elasticsearch_https_path" {
  description = "Path on each tier hostname for Elasticsearch via Caddy (TLS)."
  value       = "/es/"
}

output "elasticsearch_username" {
  description = "Elasticsearch built-in superuser used for HTTP basic auth (elastic)."
  value       = "elastic"
}

output "elasticsearch_secret_ids" {
  description = "Secret Manager secret id per tier holding that VM's elasticsearch user password (for PaaS / Cloud Run)."
  value       = { for k, v in google_secret_manager_secret.elasticsearch : k => v.secret_id }
}

output "paas_elasticsearch_env_hint" {
  description = "Example env for Cloud Run / Hibernate Search against a tier (replace tier and use secret as ELASTICSEARCH_PASSWORD)."
  value = {
    for k in keys(local.tiers_enabled) : k => {
      ELASTICSEARCH_HOSTS     = "${k}-iaas.${var.iaas_domain_suffix}:443"
      ELASTICSEARCH_PROTOCOL  = "https"
      ELASTICSEARCH_PATH_PREFIX = "/es"
      ELASTICSEARCH_USERNAME  = "elastic"
      ELASTICSEARCH_PASSWORD  = "<from Secret Manager: ${var.instance_name_prefix}-elasticsearch-${k}>"
    }
  }
}
