resource "google_secret_manager_secret" "gcp_sa" {
  secret_id = "${var.instance_name}-gcp-sa-json"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "gcp_sa" {
  secret      = google_secret_manager_secret.gcp_sa.id
  secret_data = file(var.gcp_sa_json_file)
}

resource "google_secret_manager_secret_iam_member" "vm_sa_json" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.gcp_sa.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.es_vm.email}"

  depends_on = [google_service_account.es_vm]
}

resource "random_password" "elastic" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "elastic_password" {
  secret_id = "${var.instance_name}-elastic-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "elastic_password" {
  secret      = google_secret_manager_secret.elastic_password.id
  secret_data = random_password.elastic.result
}

resource "google_secret_manager_secret_iam_member" "vm_elastic_password" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.elastic_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.es_vm.email}"

  depends_on = [google_service_account.es_vm]
}

resource "google_secret_manager_secret_iam_member" "elastic_password_accessor" {
  for_each = toset(var.secret_accessor_members)

  project   = var.project_id
  secret_id = google_secret_manager_secret.elastic_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value
}

resource "google_secret_manager_secret" "ghcr_token" {
  count = local.ghcr_enabled ? 1 : 0

  secret_id = "${var.instance_name}-ghcr-token"

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
  member    = "serviceAccount:${google_service_account.es_vm.email}"

  depends_on = [google_service_account.es_vm]
}
