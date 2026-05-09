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

module "cloudsql" {
  source     = "../../modules/cloudsql"
  project_id = var.project_id
  region     = var.region

  instance_name        = var.cloudsql.instance_name
  database_version     = var.cloudsql.database_version
  tier                 = var.cloudsql.tier
  disk_size_gb         = var.cloudsql.disk_size_gb
  disk_autoresize      = var.cloudsql.disk_autoresize
  availability_type    = var.cloudsql.availability_type
  shared_database_name = var.cloudsql.shared_database_name
  tenant_databases     = var.cloudsql.tenant_databases
  app_user             = var.cloudsql.app_user
  private_ip_range     = var.cloudsql.private_ip_range

  private_network = module.network.network_self_link
}

module "storage" {
  source     = "../../modules/storage"
  project_id = var.project_id
  location   = var.storage.location

  buckets = {
    images = {
      name_suffix    = "images-bucket"
      storage_class  = "STANDARD"
      versioning     = false
      uniform_access = true
      force_destroy  = false
      cors = [
        {
          origin          = ["https://k8s.tbd-htwg.de", "https://api.k8s.tbd-htwg.de"]
          method          = ["GET", "HEAD", "OPTIONS", "PUT"]
          response_header = ["Content-Type", "Authorization"]
          max_age_seconds = 3600
        }
      ]
    }
    frontend_assets = {
      name_suffix    = "frontend-bucket"
      storage_class  = "STANDARD"
      versioning     = true
      uniform_access = true
      force_destroy  = false
      cors           = []
    }
    terraform_state = {
      name_suffix    = "tfstate"
      storage_class  = "STANDARD"
      versioning     = true
      uniform_access = true
      force_destroy  = false
      cors           = []
    }
  }
}

module "kms" {
  source     = "../../modules/kms"
  project_id = var.project_id

  enabled         = var.kms.enabled
  location        = var.kms.location
  key_ring_name   = var.kms.key_ring_name
  crypto_key_name = var.kms.crypto_key_name
}
