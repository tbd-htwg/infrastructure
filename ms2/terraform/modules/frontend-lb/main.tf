locals {
  api_backend_neg_self_links = var.api_backend_neg_self_links
  host_api_backend_internet_endpoints = {
    for key, endpoint in var.host_api_backend_internet_endpoints : key => endpoint
    if endpoint.ip != ""
  }
  frontend_domains            = distinct(concat([var.frontend_domain], var.additional_frontend_domains))
  certificate_domains         = distinct(var.certificate_domains)
  certificate_auth_domains    = toset([for domain in local.certificate_domains : trimprefix(domain, "*.")])
  has_api_internet_endpoint   = var.api_backend_internet_endpoint_ip != null && var.api_backend_internet_endpoint_ip != ""
  api_backend_internet_groups = local.has_api_internet_endpoint ? [google_compute_global_network_endpoint_group.api_internet[0].id] : []
  api_backend_groups          = concat(local.api_backend_neg_self_links, local.api_backend_internet_groups)
  has_api_backend             = length(local.api_backend_groups) > 0
  has_internet_api_backend    = local.has_api_internet_endpoint || length(local.host_api_backend_internet_endpoints) > 0
  needs_api_health_check      = length(local.api_backend_neg_self_links) > 0
  keep_api_health_check       = local.needs_api_health_check || local.has_internet_api_backend
}

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
  count   = local.keep_api_health_check ? 1 : 0
  project = var.project_id
  name    = "api-backend-hc"

  http_health_check {
    port         = var.api_health_check_port
    request_path = var.api_health_check_path
  }
}

resource "google_compute_firewall" "api_health_checks" {
  count   = length(local.api_backend_neg_self_links) == 0 ? 0 : 1
  project = var.project_id
  name    = "allow-api-backend-health-checks"
  network = var.network_self_link

  direction     = "INGRESS"
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]

  allow {
    protocol = "tcp"
    ports    = ["8080", "8081", "8082", "8088"]
  }
}

resource "google_compute_global_network_endpoint_group" "api_internet" {
  count                 = local.has_api_internet_endpoint ? 1 : 0
  project               = var.project_id
  name                  = "standard-api-router-internet-neg"
  network_endpoint_type = "INTERNET_IP_PORT"
  default_port          = var.api_backend_internet_endpoint_port
}

resource "google_compute_global_network_endpoint" "api_internet" {
  count                         = local.has_api_internet_endpoint ? 1 : 0
  project                       = var.project_id
  global_network_endpoint_group = google_compute_global_network_endpoint_group.api_internet[0].name
  ip_address                    = var.api_backend_internet_endpoint_ip
  port                          = var.api_backend_internet_endpoint_port
}

resource "google_compute_global_network_endpoint_group" "host_api_internet" {
  for_each              = local.host_api_backend_internet_endpoints
  project               = var.project_id
  name                  = "api-${each.key}-internet-neg"
  network_endpoint_type = "INTERNET_IP_PORT"
  default_port          = each.value.port
}

resource "google_compute_global_network_endpoint" "host_api_internet" {
  for_each                      = local.host_api_backend_internet_endpoints
  project                       = var.project_id
  global_network_endpoint_group = google_compute_global_network_endpoint_group.host_api_internet[each.key].name
  ip_address                    = each.value.ip
  port                          = each.value.port
}

resource "google_compute_backend_service" "api" {
  count                 = local.has_api_backend ? 1 : 0
  project               = var.project_id
  name                  = local.has_api_internet_endpoint ? "standard-api-router-backend-service" : "api-backend-service"
  protocol              = "HTTP"
  load_balancing_scheme = local.has_api_internet_endpoint ? "EXTERNAL_MANAGED" : "EXTERNAL"
  timeout_sec           = 30

  dynamic "backend" {
    for_each = local.api_backend_neg_self_links
    content {
      group                 = backend.value
      balancing_mode        = "RATE"
      max_rate_per_endpoint = 100
    }
  }

  dynamic "backend" {
    for_each = local.api_backend_internet_groups
    content {
      group = backend.value
    }
  }

  health_checks = local.needs_api_health_check ? [google_compute_health_check.api[0].self_link] : null

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_backend_service" "host_api" {
  for_each              = local.host_api_backend_internet_endpoints
  project               = var.project_id
  name                  = "api-${each.key}-backend-service"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30

  backend {
    group = google_compute_global_network_endpoint_group.host_api_internet[each.key].id
  }

  # Google Cloud does not allow health checks on global external HTTP backend
  # services when the backend is an Internet NEG.

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_url_map" "frontend" {
  project         = var.project_id
  name            = "frontend-url-map"
  default_service = google_compute_backend_bucket.frontend.id
  depends_on      = [google_compute_backend_service.api, google_compute_backend_service.host_api]

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
      for_each = local.has_api_backend ? [1] : []
      content {
        paths   = var.api_paths
        service = google_compute_backend_service.api[0].id
      }
    }

  }

  host_rule {
    hosts        = local.frontend_domains
    path_matcher = "frontend"
  }

  dynamic "path_matcher" {
    for_each = local.host_api_backend_internet_endpoints
    content {
      name            = "frontend-${path_matcher.key}"
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

      path_rule {
        paths   = var.api_paths
        service = google_compute_backend_service.host_api[path_matcher.key].id
      }
    }
  }

  dynamic "host_rule" {
    for_each = local.host_api_backend_internet_endpoints
    content {
      hosts        = host_rule.value.hostnames
      path_matcher = "frontend-${host_rule.key}"
    }
  }
}

resource "google_certificate_manager_dns_authorization" "frontend" {
  for_each = local.certificate_auth_domains

  project     = var.project_id
  name        = "frontend-${replace(each.value, ".", "-")}-dns-auth"
  description = "DNS authorization for ${each.value}"
  domain      = each.value
  type        = "FIXED_RECORD"
}

resource "google_dns_record_set" "frontend_certificate_authorization" {
  for_each = google_certificate_manager_dns_authorization.frontend

  project      = var.project_id
  managed_zone = var.dns_zone_name
  name         = each.value.dns_resource_record[0].name
  type         = each.value.dns_resource_record[0].type
  ttl          = 300
  rrdatas      = [each.value.dns_resource_record[0].data]
}

resource "google_certificate_manager_certificate" "frontend" {
  project     = var.project_id
  name        = "frontend-wildcard-cert"
  description = "Wildcard certificate for the shared frontend load balancer"

  managed {
    domains            = local.certificate_domains
    dns_authorizations = [for authorization in google_certificate_manager_dns_authorization.frontend : authorization.id]
  }

  depends_on = [google_dns_record_set.frontend_certificate_authorization]
}

resource "google_certificate_manager_certificate_map" "frontend" {
  project     = var.project_id
  name        = "frontend-certificate-map"
  description = "Certificate map for the shared frontend load balancer"
}

resource "google_certificate_manager_certificate_map_entry" "frontend" {
  for_each = toset(local.certificate_domains)

  project      = var.project_id
  name         = substr("frontend-${replace(replace(each.value, "*.", "wildcard-"), ".", "-")}", 0, 63)
  description  = "TLS certificate mapping for ${each.value}"
  map          = google_certificate_manager_certificate_map.frontend.name
  certificates = [google_certificate_manager_certificate.frontend.id]
  hostname     = each.value

  lifecycle {
    precondition {
      condition     = google_certificate_manager_certificate.frontend.managed[0].state == "ACTIVE"
      error_message = "The frontend wildcard certificate must be ACTIVE before it can replace the legacy load-balancer certificate. Apply the certificate target first, wait for issuance, then apply the full configuration."
    }
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
  project               = var.project_id
  name                  = "frontend-http-managed-rule"
  target                = google_compute_target_http_proxy.frontend_http_redirect.id
  port_range            = "80"
  ip_address            = google_compute_global_address.frontend_ip.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_target_https_proxy" "frontend_certificate_manager" {
  project         = var.project_id
  name            = "frontend-https-proxy-cm"
  url_map         = google_compute_url_map.frontend.id
  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.frontend.id}"

  depends_on = [google_certificate_manager_certificate_map_entry.frontend]
}

resource "google_compute_global_forwarding_rule" "frontend_https" {
  project               = var.project_id
  name                  = "frontend-https-managed-rule"
  target                = google_compute_target_https_proxy.frontend_certificate_manager.id
  port_range            = "443"
  ip_address            = google_compute_global_address.frontend_ip.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_dns_record_set" "frontend" {
  project      = var.project_id
  name         = "${var.frontend_domain}."
  type         = "A"
  ttl          = 300
  managed_zone = var.dns_zone_name
  rrdatas      = [google_compute_global_address.frontend_ip.address]
}
