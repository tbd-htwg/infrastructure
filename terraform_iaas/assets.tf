resource "google_storage_bucket" "assets" {
  name                        = local.assets_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false

  depends_on = [google_project_service.storage]
}

resource "google_storage_bucket_iam_member" "vm_assets_reader" {
  bucket = google_storage_bucket.assets.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.iaas_vm.email}"

  depends_on = [google_service_account.iaas_vm]
}

resource "google_storage_bucket_object" "docker_compose" {
  name   = "docker-compose.yml"
  bucket = google_storage_bucket.assets.name
  source = "${path.module}/../docker-compose.yml"
}

resource "google_storage_bucket_object" "docker_compose_iaas" {
  name   = "docker-compose.iaas.yml"
  bucket = google_storage_bucket.assets.name
  source = "${path.module}/docker-compose.iaas.yml"
}

resource "google_storage_bucket_object" "caddyfile" {
  name   = "Caddyfile"
  bucket = google_storage_bucket.assets.name
  source = "${path.module}/Caddyfile.iaas"
}

resource "google_storage_bucket_object" "bootstrap_compose" {
  name   = "bootstrap-compose.sh"
  bucket = google_storage_bucket.assets.name
  source = "${path.module}/scripts/bootstrap-compose.sh"
}
