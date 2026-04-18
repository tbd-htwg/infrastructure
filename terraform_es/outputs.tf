output "instance_name" {
  description = "GCE instance name."
  value       = google_compute_instance.es_gateway.name
}

output "external_ip" {
  description = "Public IPv4 of the Elasticsearch gateway VM."
  value       = google_compute_instance.es_gateway.network_interface[0].access_config[0].nat_ip
}

output "elasticsearch_fqdn" {
  description = "Public hostname for HTTPS Elasticsearch (Caddy /es/)."
  value       = var.elasticsearch_fqdn
}

output "assets_bucket" {
  description = "GCS bucket with compose files and bootstrap script."
  value       = google_storage_bucket.assets.name
}

output "gcp_sa_secret_id" {
  description = "Secret Manager id for the Caddy DNS-01 service account JSON."
  value       = google_secret_manager_secret.gcp_sa.secret_id
}

output "elastic_password_secret_id" {
  description = "Secret Manager id for the elastic user password (use with stage2 remote_elasticsearch.password_secret_id)."
  value       = google_secret_manager_secret.elastic_password.secret_id
}

output "elasticsearch_https_url" {
  description = "Base URL for Hibernate Search (path_prefix /es)."
  value       = "https://${var.elasticsearch_fqdn}/es/"
}

output "vm_service_account" {
  description = "Service account email attached to the VM."
  value       = google_service_account.es_vm.email
}

output "compose_bootstrap_hint" {
  description = "Re-run bootstrap on the VM after metadata changes."
  value       = <<-EOT
    Metadata keys es_* are set by Terraform. After apply, reset the instance or SSH and run:
    sudo gsutil cp gs://${google_storage_bucket.assets.name}/bootstrap-compose.sh /tmp/ && sudo bash /tmp/bootstrap-compose.sh
    Zone: ${var.zone}. Logs: /var/log/es-bootstrap.log
  EOT
}

output "remote_elasticsearch_hint" {
  description = "Values for PaaS stage2 variable remote_elasticsearch (password from Secret Manager)."
  value = {
    hosts              = "${var.elasticsearch_fqdn}:443"
    password_secret_id = google_secret_manager_secret.elastic_password.secret_id
    protocol           = "https"
    path_prefix        = "/es"
    username           = "elastic"
  }
}
