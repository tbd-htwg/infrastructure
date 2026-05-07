provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

locals {
  startup_script = templatefile("${path.module}/startup.sh.tftpl", {
    repo_url                       = var.infrastructure_repo_url
    repo_branch                    = var.infrastructure_repo_branch
    repo_subdir                    = var.infrastructure_repo_subdir
    vm_user                        = var.vm_user
    caddy_domain                   = var.caddy_domain
    gcp_project                    = var.gcp_project
    google_application_credentials = var.google_application_credentials
    postgres_db                    = var.postgres_db
    postgres_user                  = var.postgres_user
    postgres_password_secret_id    = var.postgres_password_secret_id
    elastic_password               = var.elastic_password
    elasticsearch_password_secret  = var.elasticsearch_password_secret_id
    elasticsearch_username         = var.elasticsearch_username
    elasticsearch_path_prefix      = var.elasticsearch_path_prefix
    data_disk_name                 = var.data_disk_name
    ghcr_username                  = var.ghcr_username
    ghcr_token                     = var.ghcr_token
  })

  instance_metadata = merge(
    var.enable_oslogin ? { "enable-oslogin" = "TRUE" } : {},
    var.metadata_ssh_keys == "" ? {} : { "ssh-keys" = var.metadata_ssh_keys }
  )
}

resource "google_compute_address" "vm" {
  count  = var.create_static_ip ? 1 : 0
  name   = var.static_ip_name
  region = var.region
}

resource "google_compute_instance" "vm" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = var.tags

  boot_disk {
    initialize_params {
      image = var.boot_image
      size  = var.boot_disk_size_gb
    }
  }


  network_interface {
    network    = var.network
    subnetwork = var.subnetwork

    access_config {
      nat_ip = var.create_static_ip ? google_compute_address.vm[0].address : null
    }
  }

  metadata_startup_script = local.startup_script
  metadata                = local.instance_metadata

  dynamic "service_account" {
    for_each = var.service_account_email == null ? [] : [var.service_account_email]
    content {
      email  = service_account.value
      scopes = var.service_account_scopes
    }
  }
}

resource "google_compute_disk" "data" {
  name = var.data_disk_name
  type = var.data_disk_type
  zone = var.zone
  size = var.data_disk_size_gb
}

resource "google_compute_attached_disk" "data" {
  disk        = google_compute_disk.data.id
  instance    = google_compute_instance.vm.id
  device_name = var.data_disk_name
  mode        = "READ_WRITE"
}

resource "google_project_iam_member" "vm_secretmanager" {
  count   = var.grant_secretmanager_access && var.service_account_email != null ? 1 : 0
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${var.service_account_email}"
  project = var.project_id
}

resource "google_project_iam_member" "vm_dns_admin" {
  count   = var.grant_dns_admin && var.service_account_email != null ? 1 : 0
  role    = "roles/dns.admin"
  member  = "serviceAccount:${var.service_account_email}"
  project = var.project_id
}

resource "google_project_iam_member" "vm_log_writer" {
  count   = var.grant_log_writer && var.service_account_email != null ? 1 : 0
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${var.service_account_email}"
  project = var.project_id
}

resource "google_dns_record_set" "vm_a" {
  count        = var.manage_dns ? 1 : 0
  name         = var.dns_record_name
  managed_zone = var.dns_zone
  type         = "A"
  ttl          = var.dns_ttl
  rrdatas = [
    var.create_static_ip ? google_compute_address.vm[0].address : google_compute_instance.vm.network_interface[0].access_config[0].nat_ip,
  ]
}

resource "google_compute_firewall" "allow_http_https" {
  count   = var.create_firewall_rules ? 1 : 0
  name    = "${var.instance_name}-allow-http-https"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  target_tags   = var.tags
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_ssh" {
  count   = var.create_firewall_rules ? 1 : 0
  name    = "${var.instance_name}-allow-ssh"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags   = var.tags
  source_ranges = var.allow_ssh_cidrs
}
