resource "google_compute_global_address" "frontend_ip" {
  project = var.project_id
  name    = "frontend-lb-ip"
}

resource "google_compute_backend_bucket" "frontend" {
  project     = var.project_id
  name        = "frontend-backend-bucket"
  bucket_name = var.bucket_name
  enable_cdn  = var.enable_cdn
}

resource "google_compute_health_check" "api" {
  count   = var.api_backend_neg_self_link == null ? 0 : 1
  project = var.project_id
  name    = "api-backend-hc"

  http_health_check {
    port         = var.api_health_check_port
    request_path = var.api_health_check_path
  }
}

resource "google_compute_backend_service" "api" {
  count       = var.api_backend_neg_self_link == null ? 0 : 1
  project     = var.project_id
  name        = "api-backend-service"
  protocol    = "HTTP"
  timeout_sec = 30

  backend {
    group = var.api_backend_neg_self_link
    balancing_mode = "RATE"
    max_rate_per_endpoint = 100
  }

  health_checks = [google_compute_health_check.api[0].self_link]
}

resource "google_compute_url_map" "frontend" {
  project         = var.project_id
  name            = "frontend-url-map"
  default_service = google_compute_backend_bucket.frontend.id

  dynamic "host_rule" {
    for_each = var.api_backend_neg_self_link == null ? [] : [1]
    content {
      hosts        = [var.frontend_domain]
      path_matcher = "api"
    }
  }

  dynamic "path_matcher" {
    for_each = var.api_backend_neg_self_link == null ? [] : [1]
    content {
      name            = "api"
      default_service = google_compute_backend_bucket.frontend.id
      path_rule {
        paths   = var.api_paths
        service = google_compute_backend_service.api[0].id
      }
    }
  }
}

resource "google_compute_managed_ssl_certificate" "frontend" {
  project = var.project_id
  name    = "frontend-cert"

  managed {
    domains = [var.frontend_domain]
  }
}

resource "google_compute_target_https_proxy" "frontend" {
  project          = var.project_id
  name             = "frontend-https-proxy"
  url_map          = google_compute_url_map.frontend.id
  ssl_certificates = [google_compute_managed_ssl_certificate.frontend.id]
}

resource "google_compute_global_forwarding_rule" "frontend_https" {
  project    = var.project_id
  name       = "frontend-https-rule"
  target     = google_compute_target_https_proxy.frontend.id
  port_range = "443"
  ip_address = google_compute_global_address.frontend_ip.address
}

resource "google_dns_record_set" "frontend" {
  project      = var.project_id
  name         = "${var.frontend_domain}."
  type         = "A"
  ttl          = 300
  managed_zone = var.dns_zone_name
  rrdatas      = [google_compute_global_address.frontend_ip.address]
}
