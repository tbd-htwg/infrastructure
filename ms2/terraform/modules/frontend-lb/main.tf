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

resource "google_compute_firewall" "api_health_checks" {
  count   = var.api_backend_neg_self_link == null ? 0 : 1
  project = var.project_id
  name    = "allow-api-backend-health-checks"
  network = var.network_self_link

  direction     = "INGRESS"
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]

  allow {
    protocol = "tcp"
    ports    = ["8080", "8081", "8082"]
  }
}

resource "google_compute_backend_service" "api" {
  count       = var.api_backend_neg_self_link == null ? 0 : 1
  project     = var.project_id
  name        = "api-backend-service"
  protocol    = "HTTP"
  timeout_sec = 30

  backend {
    group                 = var.api_backend_neg_self_link
    balancing_mode        = "RATE"
    max_rate_per_endpoint = 100
  }

  health_checks = [google_compute_health_check.api[0].self_link]
}

resource "google_compute_url_map" "frontend" {
  project         = var.project_id
  name            = "frontend-url-map"
  default_service = google_compute_backend_bucket.frontend.id
  depends_on      = [google_compute_backend_service.api]

  path_matcher {
    name = "frontend"

    default_service = google_compute_backend_bucket.frontend.id

    path_rule {
      paths = ["/"]

      url_redirect {
        path_redirect          = "/index.html"
        redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
        strip_query            = false
      }
    }

    path_rule {
      paths   = ["/assets/*", "/favicon.svg", "/cloud-regular-full.svg", "/index.html"]
      service = google_compute_backend_bucket.frontend.id
    }

    dynamic "path_rule" {
      for_each = var.api_backend_neg_self_link == null ? [] : [1]
      content {
        paths   = var.api_paths
        service = google_compute_backend_service.api[0].id
      }
    }

  }

  host_rule {
    hosts        = [var.frontend_domain]
    path_matcher = "frontend"
  }
}

resource "google_compute_managed_ssl_certificate" "frontend" {
  count   = var.secondary_managed_ssl_certificate_name == null ? 1 : 0
  project = var.project_id
  name    = "frontend-cert"

  managed {
    domains = [var.frontend_domain]
  }
}

resource "google_compute_managed_ssl_certificate" "frontend_secondary" {
  count   = var.secondary_managed_ssl_certificate_name == null ? 0 : 1
  project = var.project_id
  name    = var.secondary_managed_ssl_certificate_name

  managed {
    domains = [var.frontend_domain]
  }
}

resource "google_compute_url_map" "frontend_http_redirect" {
  project = var.project_id
  name    = "frontend-http-redirect-url-map"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "frontend_http_redirect" {
  project = var.project_id
  name    = "frontend-http-redirect-proxy"
  url_map = google_compute_url_map.frontend_http_redirect.id
}

resource "google_compute_global_forwarding_rule" "frontend_http" {
  project    = var.project_id
  name       = "frontend-http-rule"
  target     = google_compute_target_http_proxy.frontend_http_redirect.id
  port_range = "80"
  ip_address = google_compute_global_address.frontend_ip.address
}

resource "google_compute_target_https_proxy" "frontend" {
  project          = var.project_id
  name             = "frontend-https-proxy"
  url_map          = google_compute_url_map.frontend.id
  ssl_certificates = var.secondary_managed_ssl_certificate_name == null ? [google_compute_managed_ssl_certificate.frontend[0].id] : [google_compute_managed_ssl_certificate.frontend_secondary[0].id]
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
