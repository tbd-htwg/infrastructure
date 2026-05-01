# HTTPS LB + Cloud CDN + managed SSL for the React SPA, with host-based routing that sends
# cloud_run_api_hostname to the Cloud Run backend via a serverless NEG (see frontend_lb_api.tf).
# A sibling HTTP(:80) forwarding rule permanently redirects to HTTPS on the same global IP.

resource "google_compute_global_address" "frontend_lb" {
  name    = "tbd-tf-frontend-lb-ip"
  project = var.project_id

  depends_on = [google_project_service.compute]
}

resource "google_compute_managed_ssl_certificate" "frontend" {
  name    = "tbd-tf-frontend-ssl"
  project = var.project_id

  managed {
    domains = distinct([var.frontend_hostname, var.cloud_run_api_hostname])
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_project_service.compute]
}

resource "google_compute_ssl_policy" "modern" {
  name            = "tbd-tf-modern-ssl"
  project         = var.project_id
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"

  depends_on = [google_project_service.compute]
}

resource "google_compute_backend_bucket" "frontend" {
  name             = "tbd-tf-frontend-bckt"
  project          = var.project_id
  bucket_name      = data.google_storage_bucket.frontend.name
  enable_cdn       = true
  compression_mode = "AUTOMATIC"

  cdn_policy {
    cache_mode        = "CACHE_ALL_STATIC"
    default_ttl       = 3600
    max_ttl           = 86400
    client_ttl        = 3600
    negative_caching  = true
    serve_while_stale = 86400
  }

  custom_response_headers = [
    "Strict-Transport-Security: max-age=63072000; includeSubDomains; preload",
    "X-Content-Type-Options: nosniff",
    "X-Frame-Options: DENY",
    "Referrer-Policy: strict-origin-when-cross-origin",
  ]

  depends_on = [google_project_service.compute]
}

resource "google_compute_url_map" "frontend" {
  name            = var.frontend_url_map_name
  project         = var.project_id
  default_service = google_compute_backend_bucket.frontend.id

  host_rule {
    hosts        = [var.cloud_run_api_hostname]
    path_matcher = "api"
  }

  path_matcher {
    name            = "api"
    default_service = google_compute_backend_service.api.id
  }
}

resource "google_compute_target_https_proxy" "frontend" {
  name    = "tbd-tf-frontend-https-proxy"
  project = var.project_id

  url_map          = google_compute_url_map.frontend.id
  ssl_certificates = [google_compute_managed_ssl_certificate.frontend.id]
  ssl_policy       = google_compute_ssl_policy.modern.id
  quic_override    = "ENABLE"

  depends_on = [
    google_compute_url_map.frontend,
    google_compute_managed_ssl_certificate.frontend,
  ]
}

resource "google_compute_global_forwarding_rule" "frontend_https" {
  name                  = "tbd-tf-frontend-https"
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.frontend.id
  ip_address            = google_compute_global_address.frontend_lb.address

  depends_on = [
    google_compute_target_https_proxy.frontend,
    google_compute_global_address.frontend_lb,
  ]
}

# HTTP → HTTPS redirect. A separate URL map with default_url_redirect keeps all traffic on TLS;
# port 80 exists only for the redirect itself, sharing the global IP with the HTTPS rule.
resource "google_compute_url_map" "redirect" {
  name    = "${var.frontend_url_map_name}-redirect"
  project = var.project_id

  default_url_redirect {
    https_redirect         = true
    strip_query            = false
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  name    = "tbd-tf-frontend-http-redirect-proxy"
  project = var.project_id
  url_map = google_compute_url_map.redirect.id
}

resource "google_compute_global_forwarding_rule" "frontend_http" {
  name                  = "tbd-tf-frontend-http"
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.redirect.id
  ip_address            = google_compute_global_address.frontend_lb.address

  depends_on = [
    google_compute_target_http_proxy.redirect,
    google_compute_global_address.frontend_lb,
  ]
}
