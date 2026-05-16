# Parent zone tbd-htwg.de + delegation of k8s.tbd-htwg.de to project_bootstrap child zone.
# Gateway A records are in the child zone (authoritative for *.k8s.tbd-htwg.de).

resource "google_dns_managed_zone" "parent" {
  count       = var.enable_parent_dns_zone ? 1 : 0
  project     = var.project_id
  name        = var.parent_dns_zone.name
  dns_name    = "tbd-htwg.de."
  description = var.parent_dns_zone.description
}

locals {
  child_zone_ns = [
    for ns in module.project_bootstrap.dns_zone_name_servers :
    (endswith(ns, ".") ? ns : "${ns}.")
  ]
}

resource "google_dns_record_set" "delegate_k8s_subdomain" {
  count        = var.enable_parent_dns_zone && var.enable_dns ? 1 : 0
  project      = var.project_id
  managed_zone = google_dns_managed_zone.parent[0].name
  name         = "k8s.tbd-htwg.de."
  type         = "NS"
  ttl          = 300
  rrdatas      = local.child_zone_ns

  depends_on = [module.project_bootstrap]
}

resource "google_dns_record_set" "gke_gateway_api" {
  count        = var.enable_dns && var.gke_gateway_ip != "" ? 1 : 0
  project      = var.project_id
  managed_zone = module.project_bootstrap.dns_zone_name
  name         = "api.k8s.tbd-htwg.de."
  type         = "A"
  ttl          = 300
  rrdatas      = [var.gke_gateway_ip]

  depends_on = [module.project_bootstrap]
}

resource "google_dns_record_set" "gke_gateway_social_api" {
  count        = var.enable_dns && var.gke_gateway_ip != "" ? 1 : 0
  project      = var.project_id
  managed_zone = module.project_bootstrap.dns_zone_name
  name         = "social.api.k8s.tbd-htwg.de."
  type         = "A"
  ttl          = 300
  rrdatas      = [var.gke_gateway_ip]

  depends_on = [module.project_bootstrap]
}

resource "google_dns_record_set" "gke_gateway_frontend" {
  count        = var.enable_dns && var.gke_gateway_ip != "" ? 1 : 0
  project      = var.project_id
  managed_zone = module.project_bootstrap.dns_zone_name
  name         = "k8s.tbd-htwg.de."
  type         = "A"
  ttl          = 300
  rrdatas      = [var.gke_gateway_ip]

  depends_on = [module.project_bootstrap]
}
