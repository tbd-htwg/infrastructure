resource "google_secret_manager_secret" "tripplanning_env" {
  secret_id = "${var.instance_name_prefix}-tripplanning-env"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "tripplanning_env" {
  secret      = google_secret_manager_secret.tripplanning_env.id
  secret_data = file(var.tripplanning_env_file)
}

resource "google_secret_manager_secret" "gcp_sa" {
  secret_id = "${var.instance_name_prefix}-gcp-sa-json"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "gcp_sa" {
  secret      = google_secret_manager_secret.gcp_sa.id
  secret_data = file(var.gcp_sa_json_file)
}

resource "google_secret_manager_secret_iam_member" "vm_env" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.tripplanning_env.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.iaas_vm.email}"

  depends_on = [google_service_account.iaas_vm]
}

resource "google_secret_manager_secret_iam_member" "vm_sa_json" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.gcp_sa.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.iaas_vm.email}"

  depends_on = [google_service_account.iaas_vm]
}

resource "google_secret_manager_secret" "ghcr_token" {
  count = local.ghcr_enabled ? 1 : 0

  secret_id = "${var.instance_name_prefix}-ghcr-token"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "ghcr_token" {
  count = local.ghcr_enabled ? 1 : 0

  secret      = google_secret_manager_secret.ghcr_token[0].id
  secret_data = trimspace(file(var.ghcr_token_file))
}

resource "google_secret_manager_secret_iam_member" "vm_ghcr_token" {
  count = local.ghcr_enabled ? 1 : 0

  project   = var.project_id
  secret_id = google_secret_manager_secret.ghcr_token[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.iaas_vm.email}"

  depends_on = [google_service_account.iaas_vm]
}
