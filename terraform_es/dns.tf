data "google_dns_managed_zone" "main" {
  count = var.manage_cloud_dns_records ? 1 : 0

  name    = var.dns_managed_zone_name
  project = var.project_id

  depends_on = [google_project_service.dns]
}

resource "google_dns_record_set" "elasticsearch" {
  count = var.manage_cloud_dns_records ? 1 : 0

  managed_zone = data.google_dns_managed_zone.main[0].name
  name         = "${var.elasticsearch_fqdn}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_instance.es_gateway.network_interface[0].access_config[0].nat_ip]

  depends_on = [
    google_project_service.dns,
    google_compute_instance.es_gateway,
  ]
}
