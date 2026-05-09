resource "google_container_cluster" "autopilot" {
  project             = var.project_id
  name                = var.cluster_name
  location            = var.region
  enable_autopilot    = true
  deletion_protection = false

  network    = var.network_self_link
  subnetwork = var.subnet_self_link

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  release_channel {
    channel = var.release_channel
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  gateway_api_config {
    channel = var.enable_gateway_api ? "CHANNEL_STANDARD" : "CHANNEL_DISABLED"
  }

  private_cluster_config {
    enable_private_nodes    = var.private_cluster
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }
}
