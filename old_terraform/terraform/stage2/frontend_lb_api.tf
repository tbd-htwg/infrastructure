# Host-based API path on the shared HTTPS LB: serverless NEG → Cloud Run, with request logging,
# security response headers and an optional Cloud Armor policy for WAF + rate limiting.

resource "google_compute_region_network_endpoint_group" "api" {
  name                  = "tbd-tf-api-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  project               = var.project_id

  cloud_run {
    service = google_cloud_run_v2_service.backend.name
  }

  depends_on = [
    google_cloud_run_v2_service.backend,
    google_project_service.compute,
  ]
}

resource "google_compute_backend_service" "api" {
  name                  = "tbd-tf-api-backend"
  project               = var.project_id
  protocol              = "HTTPS"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30

  backend {
    group = google_compute_region_network_endpoint_group.api.id
  }

  security_policy = var.enable_cloud_armor ? google_compute_security_policy.api[0].id : null

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  custom_response_headers = [
    "Strict-Transport-Security: max-age=63072000; includeSubDomains; preload",
    "X-Content-Type-Options: nosniff",
  ]

  depends_on = [google_compute_region_network_endpoint_group.api]
}

# Optional Cloud Armor: OWASP preconfigured WAF expressions + per-IP rate limit. Opt-in via
# var.enable_cloud_armor so teams can toggle it without restructuring resources.
resource "google_compute_security_policy" "api" {
  count   = var.enable_cloud_armor ? 1 : 0
  name    = "tbd-tf-api-armor"
  project = var.project_id

  # OWASP Top 10: SQLi
  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-v33-stable')"
      }
    }
    description = "Block SQL injection patterns (OWASP preconfigured WAF)"
  }

  # OWASP Top 10: XSS
  rule {
    action   = "deny(403)"
    priority = 1001
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-v33-stable')"
      }
    }
    description = "Block XSS patterns (OWASP preconfigured WAF)"
  }

  # Per-IP rate limit (rate_based_ban with enforce_on_key = "IP").
  rule {
    action   = "rate_based_ban"
    priority = 2000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = var.cloud_armor_rate_limit_rps
        interval_sec = 60
      }
      ban_duration_sec = 600
      conform_action   = "allow"
      exceed_action    = "deny(429)"
    }
    description = "Throttle abusive clients by source IP"
  }

  # Default allow (required: priority 2147483647).
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow"
  }
}
