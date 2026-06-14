locals {
  host_base            = trimsuffix(var.host_base, ".")
  enterprise_host_base = trimsuffix(var.enterprise_host_base, ".")
  fqdn                 = var.tier == "ENTERPRISE" ? "${var.slug}.${local.enterprise_host_base}." : "${var.slug}.${local.host_base}."
  ip_address           = var.tier == "ENTERPRISE" ? var.enterprise_lb_ip : var.standard_lb_ip
}

resource "google_dns_record_set" "tenant_a" {
  project      = var.project_id
  name         = local.fqdn
  type         = "A"
  ttl          = 300
  managed_zone = var.dns_zone_name
  rrdatas      = [local.ip_address]
}
