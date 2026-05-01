terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket  = "project-9118634e-c9f1-4f29-804-tf-state"
    prefix  = "global"
  }
}

provider "google" {
  project = "project-9118634e-c9f1-4f29-804"
  region  = "europe-west1"
}

# Artifact Registry
resource "google_artifact_registry_repository" "repo" {
  location      = "europe-west1"
  repository_id = "tripplanning"
  format        = "DOCKER"
}

# DNS Zone
resource "google_dns_managed_zone" "main" {
  name     = "tbd-example-zone"
  dns_name = "tbd-htwg.de."
}

# Workload Identity (GitHub Actions)
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
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

  attribute_condition = "assertion.repository_owner == 'tbd-htwg'"
}