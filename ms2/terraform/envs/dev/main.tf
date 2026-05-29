provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "current" {
  project_id = var.project_id
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
      name = "tripplanning-google-maps-api-key"
    },
    {
      name = "tripplanning-viator-api-key"
    },
    {
      name = "tripplanning-ghcr-pull-dockerconfigjson"
    },
    {
      name = "tripplanning-auth-test-bearer-token"
    },
  ]

  iam_bindings = {
    "roles/datastore.user" = [
      "serviceAccount:${local.service_account_emails["workload"]}",
    ]
    "roles/secretmanager.secretAccessor" = [
      "serviceAccount:${local.service_account_emails["workload"]}",
      "serviceAccount:${local.service_account_emails["secrets_deployer"]}",
    ]
    "roles/secretmanager.admin" = [
      "serviceAccount:${local.service_account_emails["secrets_deployer"]}",
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

  firestore = {
    enabled     = var.firestore.enabled
    database_id = var.firestore.database_id
    location_id = var.firestore.location_id
    indexes = {
      comments_by_trip_created_at = {
        collection  = "comments"
        query_scope = "COLLECTION"
        fields = [
          {
            field_path = "tripId"
            order      = "ASCENDING"
          },
          {
            field_path = "createdAt"
            order      = "DESCENDING"
          },
          {
            field_path = "__name__"
            order      = "DESCENDING"
          },
        ]
      }
    }
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
          origin          = ["https://k8s.tbd-htwg.de"]
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
      public_read    = true
      website = {
        main_page_suffix = "index.html"
        not_found_page   = "index.html"
      }
      cors = []
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

resource "google_storage_bucket_iam_member" "images_bucket_signer_viewer" {
  bucket = module.storage.bucket_names["images"]
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${local.service_account_emails["image_url_sig"]}"
}

resource "google_storage_bucket_iam_member" "images_bucket_signer_creator" {
  bucket = module.storage.bucket_names["images"]
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${local.service_account_emails["image_url_sig"]}"
}

resource "google_service_account_iam_member" "image_url_sig_token_creator" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.service_account_emails["image_url_sig"]}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${local.service_account_emails["workload"]}"
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
  source                                 = "../../modules/frontend-lb"
  project_id                             = var.project_id
  frontend_domain                        = var.frontend.domain
  dns_zone_name                          = module.project_bootstrap.dns_zone_name
  bucket_name                            = module.storage.bucket_names["frontend_assets"]
  network_self_link                      = module.network.network_self_link
  enable_cdn                             = var.frontend.enable_cdn
  api_backend_neg_self_link              = try(var.frontend.api_backend_neg_self_link, null)
  api_paths                              = coalesce(try(var.frontend.api_paths, null), ["/api/*"])
  secondary_managed_ssl_certificate_name = try(var.frontend.secondary_managed_ssl_certificate_name, null)
}

resource "google_compute_global_address" "api_gateway_ip" {
  project = var.project_id
  name    = "tripplanning-api-gateway-ip"
}

resource "google_dns_record_set" "api_gateway" {
  project      = var.project_id
  name         = "api.${var.frontend.domain}."
  type         = "A"
  ttl          = 300
  managed_zone = module.project_bootstrap.dns_zone_name
  rrdatas      = [google_compute_global_address.api_gateway_ip.address]
}

module "github_wif" {
  source               = "../../modules/github-wif"
  project_id           = var.project_id
  github_owner         = var.github_wif.owner
  github_repo          = var.github_wif.repo
  pool_id              = var.github_wif.pool_id
  provider_id          = var.github_wif.provider_id
  service_account_name = var.github_wif.service_account_name
  bucket_name          = module.storage.bucket_names["frontend_assets"]
  url_map_name         = "frontend-url-map"
}

resource "google_iam_workload_identity_pool_provider" "backend" {
  project                            = var.project_id
  workload_identity_pool_id          = var.github_wif.pool_id
  workload_identity_pool_provider_id = var.backend_wif.provider_id
  display_name                       = "GitHub OIDC Backend"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.actor"      = "assertion.actor"
  }

  attribute_condition = "assertion.repository == '${var.backend_wif.owner}/${var.backend_wif.repo}'"
}

resource "google_service_account_iam_member" "backend_wif_binding" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.service_account_emails["secrets_deployer"]}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${var.github_wif.pool_id}/attribute.repository/${var.backend_wif.owner}/${var.backend_wif.repo}"
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

# Allow the trip-service Kubernetes service account to act as the GCP workload service account
resource "google_service_account_iam_member" "trip_service_wi" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.service_account_emails["workload"]}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[tripplanning-free/trip-service]"
}

# Also allow pods running with the namespace default service account to use the workload identity
resource "google_service_account_iam_member" "trip_namespace_default_wi" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.service_account_emails["workload"]}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[tripplanning-free/default]"
}

resource "google_project_iam_member" "cert_manager_dns_admin" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${local.service_account_emails["workload"]}"
}
