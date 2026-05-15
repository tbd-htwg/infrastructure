# Application workload IAM, Firestore, GCS access, and Workload Identity bindings.

resource "google_project_service" "firestore" {
  project            = var.project_id
  service            = "firestore.googleapis.com"
  disable_on_destroy = false
}

resource "google_firestore_database" "social" {
  count = var.manage_firestore_database ? 1 : 0

  project     = var.project_id
  name        = "tbd-firestore"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_project_service.firestore]
}

resource "google_secret_manager_secret" "auth_jwt" {
  project   = var.project_id
  secret_id = "tripplanning-auth-jwt-secret"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "internal_api" {
  project   = var.project_id
  secret_id = "tripplanning-internal-secret"
  replication {
    auto {}
  }
}

data "google_project" "current" {
  project_id = var.project_id
}

locals {
  workload_sa   = module.project_bootstrap.service_account_emails["workload"]
  images_bucket = try(module.storage.bucket_names["images"], "${var.project_id}-images-bucket")
  gke_node_sa   = "${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

# Autopilot kubelet pulls container images with the default compute SA, not the pod WI SA.
resource "google_project_iam_member" "gke_node_artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${local.gke_node_sa}"

  depends_on = [module.project_bootstrap]
}

resource "google_project_iam_member" "workload_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${local.workload_sa}"

  depends_on = [module.project_bootstrap]
}

resource "google_project_iam_member" "workload_datastore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${local.workload_sa}"

  depends_on = [module.project_bootstrap]
}

resource "google_storage_bucket_iam_member" "workload_images_admin" {
  bucket = local.images_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${local.workload_sa}"

  depends_on = [module.project_bootstrap, module.storage]
}

resource "google_service_account_iam_member" "workload_wi_trip" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.workload_sa}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[tripplanning/trip-service]"

  depends_on = [module.project_bootstrap]
}

resource "google_service_account_iam_member" "workload_wi_social" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.workload_sa}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[tripplanning/social-service]"

  depends_on = [module.project_bootstrap]
}

resource "google_service_account_iam_member" "workload_wi_eso" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.workload_sa}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"

  depends_on = [module.project_bootstrap]
}
