resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  project            = var.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  project            = var.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "dns" {
  count = var.manage_cloud_dns_records ? 1 : 0

  project            = var.project_id
  service            = "dns.googleapis.com"
  disable_on_destroy = false
}

resource "google_service_account" "iaas_vm" {
  account_id   = var.iaas_vm_sa_id
  display_name = "Tripplanning IaaS VM"
  project      = var.project_id

  depends_on = [google_project_service.iam]
}

resource "google_project_service" "artifactregistry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_artifact_registry_repository_iam_member" "vm_reader" {
  for_each = toset(var.artifact_registry_repository_ids)

  project    = var.project_id
  location   = var.region
  repository = each.value
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.iaas_vm.email}"

  depends_on = [
    google_project_service.artifactregistry,
    google_service_account.iaas_vm,
  ]
}

resource "google_compute_instance" "tier" {
  for_each     = local.tiers_enabled
  name         = "${var.instance_name_prefix}-${each.key}"
  machine_type = each.value.machine_type
  zone         = var.zone

  tags = [var.network_tag]

  boot_disk {
    initialize_params {
      image = var.boot_image
      size  = var.boot_disk_size_gb
      type  = "pd-standard"
    }
  }

  network_interface {
    network = "default"
    access_config {
      network_tier = "PREMIUM"
    }
  }

  service_account {
    email  = google_service_account.iaas_vm.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = merge(
    {
      enable-oslogin = "TRUE"
      es_java_opts   = each.value.es_java_opts

      # Consumed by bootstrap-compose.sh (startup and manual re-runs on the VM).
      iaas_assets_bucket           = google_storage_bucket.assets.name
      iaas_env_secret_id           = google_secret_manager_secret.tripplanning_env.secret_id
      iaas_sa_secret_id            = google_secret_manager_secret.gcp_sa.secret_id
      iaas_elasticsearch_secret_id = google_secret_manager_secret.elasticsearch[each.key].secret_id
      iaas_tier_hostname           = "${each.key}-iaas.${var.iaas_domain_suffix}"
    },
    local.ghcr_enabled ? {
      iaas_ghcr_username         = var.ghcr_username
      iaas_ghcr_token_secret_id  = google_secret_manager_secret.ghcr_token[0].secret_id
    } : {}
  )

  metadata_startup_script = templatefile("${path.module}/templates/startup.sh.tmpl", {
    assets_bucket = google_storage_bucket.assets.name
  })

  # google_compute_instance.depends_on must be a static list (no concat). GHCR secret/version is
  # still ordered before the instance when ghcr_enabled: metadata references
  # google_secret_manager_secret.ghcr_token[0].secret_id (implicit edge to the secret + version chain).
  depends_on = [
    google_project_service.compute,
    google_secret_manager_secret_version.tripplanning_env,
    google_secret_manager_secret_version.gcp_sa,
    google_secret_manager_secret_version.elasticsearch,
    google_storage_bucket_object.docker_compose,
    google_storage_bucket_object.docker_compose_iaas,
    google_storage_bucket_object.caddyfile,
    google_storage_bucket_object.bootstrap_compose,
  ]
}

resource "google_compute_firewall" "http_https" {
  name    = "${var.instance_name_prefix}-http-https"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [var.network_tag]

  depends_on = [google_project_service.compute]
}

resource "google_compute_firewall" "ssh" {
  count = var.allow_ssh_ingress ? 1 : 0

  name    = "${var.instance_name_prefix}-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = [var.network_tag]

  depends_on = [google_project_service.compute]
}
