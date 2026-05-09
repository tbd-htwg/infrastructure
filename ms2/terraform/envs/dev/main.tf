provider "google" {
  project = var.project_id
  region  = var.region
}

module "project_bootstrap" {
  source     = "../../modules/project-bootstrap"
  project_id = var.project_id

  enable_dns = var.enable_dns
  dns_zone   = var.dns_zone

  secrets = [
    {
      name = "tripplanning-db-password"
    },
    {
      name = "tbd-es-gateway-elastic-password"
    },
  ]

  iam_bindings = {
    "roles/secretmanager.secretAccessor" = [
      "serviceAccount:${local.service_account_emails["workload"]}",
    ]
    "roles/artifactregistry.reader" = [
      "serviceAccount:${local.service_account_emails["workload"]}",
    ]
  }

  log_sink = {
    enabled         = true
    name            = "project-logs"
    filter          = "resource.type=\"k8s_container\" OR resource.type=\"k8s_pod\""
    bucket_location = "EU"
  }
}

module "network" {
  source     = "../../modules/network"
  project_id = var.project_id
  region     = var.region

  network_name = var.network.name
  subnet_name  = var.network.subnet_name
  subnet_cidr  = var.network.subnet_cidr

  pods_secondary_range = {
    name = var.network.pods_secondary_name
    cidr = var.network.pods_secondary_cidr
  }

  services_secondary_range = {
    name = var.network.services_secondary_name
    cidr = var.network.services_secondary_cidr
  }
}

module "gke_autopilot" {
  source     = "../../modules/gke-autopilot"
  project_id = var.project_id
  region     = var.region

  cluster_name           = var.gke.cluster_name
  release_channel        = var.gke.release_channel
  enable_gateway_api     = var.gke.enable_gateway_api
  private_cluster        = var.gke.private_cluster
  master_ipv4_cidr_block = var.gke.master_ipv4_cidr_block

  network_self_link             = module.network.network_self_link
  subnet_self_link              = module.network.subnet_self_link
  pods_secondary_range_name     = module.network.pods_secondary_range_name
  services_secondary_range_name = module.network.services_secondary_range_name
}
