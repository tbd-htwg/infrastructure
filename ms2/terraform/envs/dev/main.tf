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
      name = "tripplanning-jwt-secret"
    },
    {
      name = "tripplanning-internal-secret"
    },
    {
      name = "tripplanning-viator-api-key"
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

module "frontend_lb" {
  source                    = "../../modules/frontend-lb"
  project_id                = var.project_id
  frontend_domain           = var.frontend.domain
  dns_zone_name             = module.project_bootstrap.dns_zone_name
  bucket_name               = module.storage.bucket_names["frontend_assets"]
  enable_cdn                = var.frontend.enable_cdn
  api_backend_neg_self_link = try(var.frontend.api_backend_neg_self_link, null)
  api_paths                 = try(var.frontend.api_paths, ["/api/*"])
}

resource "google_service_account_iam_member" "external_secrets_wi" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.service_account_emails["workload"]}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"
}

resource "google_service_account_iam_member" "cert_manager_wi" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.service_account_emails["workload"]}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[cert-manager/cert-manager]"
}

resource "google_project_iam_member" "cert_manager_dns_admin" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${local.service_account_emails["workload"]}"
}
