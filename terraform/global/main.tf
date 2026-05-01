terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "project-9118634e-c9f1-4f29-804-tf-state"
    prefix = "global"
  }
}

provider "google" {
  project = "project-9118634e-c9f1-4f29-804"
  region  = "europe-west1"
}

locals {
  project_id     = "project-9118634e-c9f1-4f29-804"
  project_number = "1001763908245"
  region         = "europe-west1"
  zone           = "europe-west1-b"
}

# Project APIs needed by the inventory resources. Keep enabled on destroy so
# teardown is not blocked by disabling APIs before dependent resources are gone.
resource "google_project_service" "apis" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
  ])

  project            = local.project_id
  service            = each.key
  disable_on_destroy = false
}

# Artifact Registry
resource "google_artifact_registry_repository" "repo" {
  location      = "europe-west1"
  repository_id = "tripplanning"
  description   = "Tripplanning container images"
  format        = "DOCKER"
}

# DNS Zone
resource "google_dns_managed_zone" "main" {
  name     = "tbd-example-zone"
  dns_name = "tbd-htwg.de."

  lifecycle {
    ignore_changes = [description]
  }
}

resource "google_dns_record_set" "es" {
  managed_zone = google_dns_managed_zone.main.name
  name         = "es.tbd-htwg.de."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_instance.es_gateway.network_interface[0].access_config[0].nat_ip]
}

resource "google_dns_record_set" "iaas" {
  managed_zone = google_dns_managed_zone.main.name
  name         = "iaas.tbd-htwg.de."
  type         = "A"
  ttl          = 300
  rrdatas      = ["34.185.182.163"]
}

resource "google_dns_record_set" "api_iaas" {
  managed_zone = google_dns_managed_zone.main.name
  name         = "api.iaas.tbd-htwg.de."
  type         = "A"
  ttl          = 300
  rrdatas      = ["34.185.182.163"]
}

resource "google_dns_record_set" "paas_stag" {
  managed_zone = google_dns_managed_zone.main.name
  name         = "paas-stag.tbd-htwg.de."
  type         = "A"
  ttl          = 300
  rrdatas      = ["34.96.64.41"]
}

resource "google_dns_record_set" "api_paas_stag" {
  managed_zone = google_dns_managed_zone.main.name
  name         = "api.paas-stag.tbd-htwg.de."
  type         = "A"
  ttl          = 300
  rrdatas      = ["34.96.64.41"]
}

# IAM
resource "google_project_iam_custom_role" "frontend_cdn_invalidator" {
  role_id     = "tripplanningFrontendCdnInvalidator"
  title       = "tripplanning Frontend CDN Invalidator"
  description = "Invalidate CDN cache and read URL maps for frontend deploy pipeline"
  permissions = [
    "compute.urlMaps.get",
    "compute.urlMaps.invalidateCache",
  ]
  stage = "GA"
}

resource "google_service_account" "tbd_es_vm" {
  account_id   = "tbd-es-vm"
  display_name = "Elasticsearch gateway VM"
}

resource "google_service_account" "caddy_cert" {
  account_id   = "caddy-cert"
  display_name = "Caddy DNS challenge"
  disabled     = true
}

resource "google_project_iam_member" "caddy_dns_admin" {
  project = local.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.caddy_cert.email}"
}

resource "google_project_iam_member" "cloudbuild_builder" {
  project = local.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${local.project_number}@cloudbuild.gserviceaccount.com"
}

# Secret Manager metadata and access. Secret values/versions are intentionally
# not hard-coded here; import existing versions or create versions from a secure
# variable store before recreating dependent workloads.
resource "google_secret_manager_secret" "tripplanning_db_password" {
  project   = local.project_id
  secret_id = "tripplanning-db-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "es_elastic_password" {
  project   = local.project_id
  secret_id = "tbd-es-gateway-elastic-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "es_gcp_sa_json" {
  project   = local.project_id
  secret_id = "tbd-es-gateway-gcp-sa-json"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "es_ghcr_token" {
  project   = local.project_id
  secret_id = "tbd-es-gateway-ghcr-token"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "es_vm_elastic_password" {
  project   = local.project_id
  secret_id = google_secret_manager_secret.es_elastic_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.tbd_es_vm.email}"
}

resource "google_secret_manager_secret_iam_member" "es_vm_gcp_sa_json" {
  project   = local.project_id
  secret_id = google_secret_manager_secret.es_gcp_sa_json.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.tbd_es_vm.email}"
}

resource "google_secret_manager_secret_iam_member" "es_vm_ghcr_token" {
  project   = local.project_id
  secret_id = google_secret_manager_secret.es_ghcr_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.tbd_es_vm.email}"
}

# Shared storage
resource "google_storage_bucket" "images" {
  name                        = "${local.project_id}-images-bucket"
  location                    = "EUROPE-WEST1"
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true

  cors {
    origin = [
      "http://localhost:5173",
      "http://127.0.0.1:5173",
      "https://tbd-htwg.de",
      "https://www.tbd-htwg.de",
      "https://iaas.tbd-htwg.de",
      "https://small-iaas.tbd-htwg.de",
      "https://medium-iaas.tbd-htwg.de",
      "https://large-iaas.tbd-htwg.de",
      "https://paas-dev.tbd-htwg.de",
      "https://paas.tbd-htwg.de",
    ]
    method          = ["OPTIONS", "PUT", "GET", "HEAD"]
    response_header = ["Content-Type", "x-goog-resumable", "x-goog-meta-*"]
    max_age_seconds = 3600
  }

  soft_delete_policy {
    retention_duration_seconds = 604800
  }
}

resource "google_storage_bucket" "es_assets" {
  name                        = "${local.project_id}-tbd-es-assets"
  location                    = "EUROPE-WEST1"
  uniform_bucket_level_access = true

  soft_delete_policy {
    retention_duration_seconds = 604800
  }
}

resource "google_storage_bucket_iam_member" "es_assets_vm_viewer" {
  bucket = google_storage_bucket.es_assets.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.tbd_es_vm.email}"
}

# Elasticsearch gateway VM
resource "google_compute_firewall" "es_gateway_http_https" {
  name          = "tbd-es-gateway-http-https"
  network       = "default"
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["tripplanning-es-gateway"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

resource "google_compute_instance" "es_gateway" {
  name         = "tbd-es-gateway"
  machine_type = "e2-standard-2"
  zone         = local.zone
  tags         = ["tripplanning-es-gateway"]

  boot_disk {
    auto_delete = true

    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/ubuntu-2204-jammy-v20260414"
      size  = 32
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = "default"
    subnetwork = "default"

    access_config {
      network_tier = "PREMIUM"
    }
  }

  service_account {
    email  = google_service_account.tbd_es_vm.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin                = "TRUE"
    es_assets_bucket              = google_storage_bucket.es_assets.name
    es_caddy_domain               = "es.tbd-htwg.de"
    es_elastic_password_secret_id = google_secret_manager_secret.es_elastic_password.secret_id
    es_gcp_sa_secret_id           = google_secret_manager_secret.es_gcp_sa_json.secret_id
    es_ghcr_token_secret_id       = google_secret_manager_secret.es_ghcr_token.secret_id
    es_ghcr_username              = "ben.b+github@posteo.de"
    es_java_opts                  = "-Xms2g -Xmx2g"
    startup-script                = <<-EOT
      #!/bin/bash
      # GCE first boot: gcloud CLI + gsutil, then bootstrap (installs Docker if needed).
      set -euo pipefail
      export DEBIAN_FRONTEND=noninteractive

      BUCKET="${local.project_id}-tbd-es-assets"

      es_log() {
        echo "[es-gce-startup] $*"
      }

      dpkg_is_busy() {
        if command -v fuser >/dev/null 2>&1; then
          fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
            || fuser /var/lib/dpkg/lock >/dev/null 2>&1
        else
          pgrep -x apt-get >/dev/null 2>&1 || pgrep -x dpkg >/dev/null 2>&1
        fi
      }

      wait_for_apt_lock() {
        local max_wait=600
        local deadline=$((SECONDS + max_wait))
        while (( SECONDS < deadline )); do
          if dpkg_is_busy; then
            es_log "Waiting for dpkg lock..."
            sleep 5
            continue
          fi
          sleep 1
          if ! dpkg_is_busy; then
            return 0
          fi
        done
        es_log "ERROR: timed out waiting for dpkg lock"
        return 1
      }

      es_log "Installing apt base + Google Cloud CLI"
      wait_for_apt_lock
      apt-get update -qq
      apt-get install -y -qq ca-certificates curl gnupg lsb-release apt-transport-https
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | gpg --dearmor -o /etc/apt/keyrings/cloud.google.gpg
      echo "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        > /etc/apt/sources.list.d/google-cloud-sdk.list
      wait_for_apt_lock
      apt-get update -qq
      apt-get install -y -qq google-cloud-cli

      es_log "Downloading bootstrap from gs://$${BUCKET}"
      gsutil cp "gs://$${BUCKET}/bootstrap-compose.sh" /tmp/es-bootstrap-compose.sh
      chmod 700 /tmp/es-bootstrap-compose.sh

      es_log "Running bootstrap-compose.sh"
      exec /tmp/es-bootstrap-compose.sh
    EOT
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = false
    enable_vtpm                 = true
  }
}

# Workload Identity (GitHub Actions)
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions Pool"
  description               = "OIDC trust for GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "attribute.actor"            = "assertion.actor"
    "attribute.aud"              = "assertion.aud"
    "attribute.ref"              = "assertion.ref"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "google.subject"             = "assertion.sub"
  }

  attribute_condition = "assertion.repository_owner=='tbd-htwg'"
  display_name        = "GitHub OIDC Provider"
  description         = "OIDC provider for GitHub Actions"
}
