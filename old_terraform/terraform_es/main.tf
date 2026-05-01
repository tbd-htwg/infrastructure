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

resource "google_service_account" "es_vm" {
  account_id   = var.es_vm_sa_id
  display_name = "Elasticsearch gateway VM"
  project      = var.project_id

  depends_on = [google_project_service.iam]
}

resource "google_compute_instance" "es_gateway" {
  name         = var.instance_name
  machine_type = var.machine_type
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
    email  = google_service_account.es_vm.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = merge(
    {
      enable-oslogin = "TRUE"
      es_java_opts   = var.es_java_opts

      es_assets_bucket              = google_storage_bucket.assets.name
      es_gcp_sa_secret_id           = google_secret_manager_secret.gcp_sa.secret_id
      es_elastic_password_secret_id = google_secret_manager_secret.elastic_password.secret_id
      es_caddy_domain               = var.elasticsearch_fqdn
    },
    local.ghcr_enabled ? {
      es_ghcr_username        = var.ghcr_username
      es_ghcr_token_secret_id = google_secret_manager_secret.ghcr_token[0].secret_id
    } : {}
  )

  metadata_startup_script = templatefile("${path.module}/templates/startup.sh.tmpl", {
    assets_bucket = google_storage_bucket.assets.name
  })

  depends_on = [
    google_project_service.compute,
    google_secret_manager_secret_version.gcp_sa,
    google_secret_manager_secret_version.elastic_password,
    google_storage_bucket_object.docker_compose,
    google_storage_bucket_object.docker_compose_gcp,
    google_storage_bucket_object.caddyfile,
    google_storage_bucket_object.bootstrap_compose,
  ]
}

resource "google_compute_firewall" "http_https" {
  name    = "${var.instance_name}-http-https"
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

  name    = "${var.instance_name}-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = [var.network_tag]

  depends_on = [google_project_service.compute]
}
