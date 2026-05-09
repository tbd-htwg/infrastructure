resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "primary" {
  project                  = var.project_id
  region                   = var.region
  name                     = var.subnet_name
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = var.pods_secondary_range.name
    ip_cidr_range = var.pods_secondary_range.cidr
  }

  secondary_ip_range {
    range_name    = var.services_secondary_range.name
    ip_cidr_range = var.services_secondary_range.cidr
  }
}

resource "google_compute_router" "router" {
  project = var.project_id
  region  = var.region
  name    = var.router_name
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  project                             = var.project_id
  region                              = var.region
  name                                = var.nat_name
  router                              = google_compute_router.router.name
  nat_ip_allocate_option              = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat  = "LIST_OF_SUBNETWORKS"
  enable_endpoint_independent_mapping = true

  subnetwork {
    name                    = google_compute_subnetwork.primary.name
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
