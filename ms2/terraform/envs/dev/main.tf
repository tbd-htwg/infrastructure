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
    {
      name = "tripplanning-platform-github-dispatch-token"
    },
  ]

  iam_bindings = {
    "roles/identityplatform.admin" = [
      "serviceAccount:${local.service_account_emails["platform-admin"]}",
      "serviceAccount:${local.service_account_emails["secrets_deployer"]}",
      "serviceAccount:${local.infra_terraform_service_account_email}",
    ]
    "roles/datastore.user" = [
      "serviceAccount:${local.service_account_emails["workload"]}",
    ]
    "roles/secretmanager.secretAccessor" = [
      "serviceAccount:${local.service_account_emails["workload"]}",
      "serviceAccount:${local.service_account_emails["secrets_deployer"]}",
    ]
    "roles/secretmanager.admin" = [
      "serviceAccount:${local.service_account_emails["secrets_deployer"]}",
      "serviceAccount:${local.infra_terraform_service_account_email}",
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

resource "google_secret_manager_secret_version" "platform_github_dispatch_token" {
  count = var.platform_github_dispatch_token == null || var.platform_github_dispatch_token == "" ? 0 : 1

  project     = var.project_id
  secret      = "projects/${var.project_id}/secrets/tripplanning-platform-github-dispatch-token"
  secret_data = var.platform_github_dispatch_token

  depends_on = [
    module.project_bootstrap,
  ]
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

  buckets = merge({
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
  }, local.enterprise_image_buckets)
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

resource "google_storage_bucket_iam_member" "enterprise_images_bucket_signer_viewer" {
  for_each = local.enterprise_image_buckets

  bucket = module.storage.bucket_names[each.key]
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${local.service_account_emails["image_url_sig"]}"
}

resource "google_storage_bucket_iam_member" "enterprise_images_bucket_signer_creator" {
  for_each = local.enterprise_image_buckets

  bucket = module.storage.bucket_names[each.key]
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
  api_backend_neg_self_links             = coalesce(try(var.frontend.api_backend_neg_self_links, null), [])
  api_paths                              = coalesce(try(var.frontend.api_paths, null), ["/api/*"])
  api_health_check_path                  = coalesce(try(var.frontend.api_health_check_path, null), "/actuator/health/readiness")
  api_health_check_port                  = coalesce(try(var.frontend.api_health_check_port, null), 8080)
  secondary_managed_ssl_certificate_name = try(var.frontend.secondary_managed_ssl_certificate_name, null)
}

resource "google_compute_address" "standard_lb_ip" {
  project = var.project_id
  region  = var.region
  name    = var.standard_load_balancer.name
}

resource "google_compute_address" "enterprise_lb_ip" {
  for_each = var.enterprise_tenants

  project = var.project_id
  region  = var.region
  name    = coalesce(try(each.value.load_balancer.name, null), "tripplanning-ent-${each.key}-lb-ip")
}

module "standard_tenant_dns" {
  for_each = var.standard_tenants
  source   = "../../modules/tenant-dns"

  project_id           = var.project_id
  slug                 = each.key
  tier                 = "STANDARD"
  dns_zone_name        = module.project_bootstrap.dns_zone_name
  host_base            = var.frontend.domain
  enterprise_host_base = "enterprise.${var.frontend.domain}"
  standard_lb_ip       = google_compute_address.standard_lb_ip.address
}

module "enterprise_tenant_dns" {
  for_each = var.enterprise_tenants
  source   = "../../modules/tenant-dns"

  project_id           = var.project_id
  slug                 = each.key
  tier                 = "ENTERPRISE"
  dns_zone_name        = module.project_bootstrap.dns_zone_name
  host_base            = var.frontend.domain
  enterprise_host_base = "enterprise.${var.frontend.domain}"
  enterprise_lb_ip     = google_compute_address.enterprise_lb_ip[each.key].address
}

resource "google_identity_platform_tenant" "standard" {
  for_each = var.standard_tenants

  project                  = var.project_id
  display_name             = each.value.identity_platform.display_name
  allow_password_signup    = each.value.identity_platform.email_password_enabled
  enable_email_link_signin = each.value.identity_platform.email_link_signin
  disable_auth             = each.value.identity_platform.auth_disabled

  depends_on = [
    module.project_bootstrap,
  ]
}

resource "google_identity_platform_tenant" "enterprise" {
  for_each = var.enterprise_tenants

  project                  = var.project_id
  display_name             = each.value.identity_platform.display_name
  allow_password_signup    = each.value.identity_platform.email_password_enabled
  enable_email_link_signin = each.value.identity_platform.email_link_signin
  disable_auth             = each.value.identity_platform.auth_disabled

  depends_on = [
    module.project_bootstrap,
  ]
}

module "standard_cloudsql" {
  count  = var.standard_cloudsql.enabled ? 1 : 0
  source = "../../modules/tenant-cloudsql"

  project_id                        = var.project_id
  region                            = var.region
  instance_name                     = var.standard_cloudsql.instance_name
  database_version                  = var.standard_cloudsql.database_version
  tier                              = var.standard_cloudsql.tier
  disk_size_gb                      = var.standard_cloudsql.disk_size_gb
  disk_autoresize                   = var.standard_cloudsql.disk_autoresize
  availability_type                 = var.standard_cloudsql.availability_type
  backup_enabled                    = var.standard_cloudsql.backup_enabled
  point_in_time_recovery_enabled    = var.standard_cloudsql.point_in_time_recovery_enabled
  private_network                   = module.network.network_self_link
  create_private_service_connection = true
  private_ip_range                  = var.standard_cloudsql.private_ip_range
  databases                         = local.standard_tenant_databases
  labels = {
    app        = "tripplanning"
    tier       = "standard"
    managed_by = "terraform"
  }

  depends_on = [
    module.project_bootstrap,
  ]
}

module "enterprise_cloudsql" {
  for_each = var.enterprise_tenants
  source   = "../../modules/tenant-cloudsql"

  project_id                        = var.project_id
  region                            = var.region
  instance_name                     = each.value.database.instance_name
  database_version                  = each.value.database.database_version
  tier                              = each.value.database.tier
  disk_size_gb                      = each.value.database.disk_size_gb
  disk_autoresize                   = each.value.database.disk_autoresize
  availability_type                 = each.value.database.availability_type
  backup_enabled                    = each.value.database.backup_enabled
  point_in_time_recovery_enabled    = each.value.database.point_in_time_recovery_enabled
  private_network                   = module.network.network_self_link
  create_private_service_connection = false
  databases                         = local.enterprise_tenant_databases[each.key]
  labels = {
    app        = "tripplanning"
    tier       = "enterprise"
    tenant_id  = each.key
    managed_by = "terraform"
  }

  depends_on = [
    module.standard_cloudsql,
  ]
}

module "platform_cloudsql" {
  source = "../../modules/tenant-cloudsql"

  project_id                        = var.project_id
  region                            = var.region
  instance_name                     = var.platform_cloudsql.instance_name
  database_version                  = var.platform_cloudsql.database_version
  tier                              = var.platform_cloudsql.tier
  disk_size_gb                      = var.platform_cloudsql.disk_size_gb
  disk_autoresize                   = var.platform_cloudsql.disk_autoresize
  availability_type                 = var.platform_cloudsql.availability_type
  backup_enabled                    = var.platform_cloudsql.backup_enabled
  point_in_time_recovery_enabled    = var.platform_cloudsql.point_in_time_recovery_enabled
  private_network                   = module.network.network_self_link
  create_private_service_connection = false
  databases = {
    platform = {
      name               = var.platform_cloudsql.database_name
      user_name          = var.platform_cloudsql.user_name
      password_secret_id = "tripplanning-platform-db-password"
    }
  }
  labels = {
    app        = "tripplanning"
    tier       = "platform"
    managed_by = "terraform"
  }

  depends_on = [
    module.standard_cloudsql,
  ]
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

  depends_on = [
    module.github_wif,
  ]
}

resource "google_service_account_iam_member" "backend_wif_binding" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.service_account_emails["secrets_deployer"]}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${var.github_wif.pool_id}/attribute.repository/${var.backend_wif.owner}/${var.backend_wif.repo}"
}

resource "google_service_account" "infra_terraform_deployer" {
  project      = var.project_id
  account_id   = var.infra_wif.service_account_name
  display_name = "Infrastructure Terraform deployer"
  description  = "GitHub Actions service account for infrastructure repo Terraform applies."
}

resource "google_iam_workload_identity_pool_provider" "infra" {
  project                            = var.project_id
  workload_identity_pool_id          = var.github_wif.pool_id
  workload_identity_pool_provider_id = var.infra_wif.provider_id
  display_name                       = "GitHub OIDC Infrastructure"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.actor"      = "assertion.actor"
  }

  attribute_condition = "assertion.repository == '${var.infra_wif.owner}/${var.infra_wif.repo}'"

  depends_on = [
    module.github_wif,
  ]
}

resource "google_service_account_iam_member" "infra_wif_binding" {
  service_account_id = google_service_account.infra_terraform_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${var.github_wif.pool_id}/attribute.repository/${var.infra_wif.owner}/${var.infra_wif.repo}"
}

resource "google_project_iam_member" "infra_terraform_project_roles" {
  for_each = local.infra_terraform_project_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.infra_terraform_deployer.email}"
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

resource "google_service_account_iam_member" "platform_service_wi" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.service_account_emails["platform-admin"]}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[tripplanning-system/platform-service]"
}

resource "google_project_iam_member" "platform_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${local.service_account_emails["platform-admin"]}"
}

resource "google_project_iam_member" "cert_manager_dns_admin" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${local.service_account_emails["workload"]}"
}

moved {
  from = terraform_data.flux_bootstrap[0]
  to   = terraform_data.flux_bootstrap
}

resource "terraform_data" "flux_bootstrap" {

  input = {
    cluster_name  = module.gke_autopilot.cluster_name
    location      = module.gke_autopilot.cluster_location
    manifest_hash = local.flux_bootstrap_hash
    manifest_dir  = local.flux_bootstrap_manifest_dir
    namespace     = var.flux_bootstrap.namespace
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      FLUX_GIT_USERNAME = var.flux_bootstrap.git_username
      FLUX_GIT_PASSWORD = var.flux_bootstrap_git_password
    }
    command = <<-EOT
      set -euo pipefail

      if ! command -v gcloud >/dev/null 2>&1; then
        echo "gcloud is required for Flux bootstrap. Install the Google Cloud CLI before running terraform apply." >&2
        exit 1
      fi

      if ! command -v kubectl >/dev/null 2>&1; then
        echo "kubectl is required for Flux bootstrap." >&2
        echo "If gcloud is package-manager managed, install: sudo apt-get install kubectl google-cloud-cli-gke-gcloud-auth-plugin" >&2
        exit 1
      fi

      gcloud container clusters get-credentials ${module.gke_autopilot.cluster_name} \
        --region ${module.gke_autopilot.cluster_location} \
        --project ${var.project_id}

      kubectl create namespace ${var.flux_bootstrap.namespace} \
        --dry-run=client \
        -o yaml | kubectl apply -f -

      if grep -q "secretRef:" ${local.flux_bootstrap_manifest_dir}/gotk-sync.yaml && [ -z "$FLUX_GIT_PASSWORD" ]; then
        echo "flux_bootstrap_git_password is required because gotk-sync.yaml references secretRef: flux-system." >&2
        exit 1
      fi

      kubectl -n ${var.flux_bootstrap.namespace} create secret generic flux-system \
        --from-literal=username="$FLUX_GIT_USERNAME" \
        --from-literal=password="$FLUX_GIT_PASSWORD" \
        --dry-run=client \
        -o yaml | kubectl apply -f -

      kubectl apply -f ${local.flux_bootstrap_manifest_dir}/gotk-components.yaml
      kubectl wait --for=condition=Established crd/gitrepositories.source.toolkit.fluxcd.io --timeout=120s
      kubectl wait --for=condition=Established crd/kustomizations.kustomize.toolkit.fluxcd.io --timeout=120s
      kubectl apply -f ${local.flux_bootstrap_manifest_dir}/gotk-sync.yaml
    EOT
  }

  depends_on = [
    module.gke_autopilot,
  ]
}
