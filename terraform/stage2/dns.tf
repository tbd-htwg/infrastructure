# Cloud DNS: create A records in an *existing* managed zone (looked up in data.tf). The zone
# itself is never created or destroyed here. Both SPA and API hostnames point at the same HTTPS
# LB IP; the LB routes by Host header to GCS (SPA) or Cloud Run (API).

resource "google_dns_record_set" "frontend" {
  count = var.manage_cloud_dns_records ? 1 : 0

  managed_zone = data.google_dns_managed_zone.main[0].name
  name         = "${var.frontend_hostname}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.frontend_lb.address]

  depends_on = [
    google_project_service.dns,
    google_compute_global_address.frontend_lb,
  ]
}

resource "google_dns_record_set" "api" {
  count = var.manage_cloud_dns_records ? 1 : 0

  managed_zone = data.google_dns_managed_zone.main[0].name
  name         = "${var.cloud_run_api_hostname}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.frontend_lb.address]

  depends_on = [
    google_project_service.dns,
    google_compute_global_address.frontend_lb,
  ]
}
