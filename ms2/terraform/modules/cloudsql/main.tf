resource "google_compute_global_address" "private_service_range" {
  project       = var.project_id
  name          = "${var.instance_name}-private-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.private_network
  address       = var.private_ip_range
}

resource "google_service_networking_connection" "private_service_connection" {
  network                 = var.private_network
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
}

resource "google_sql_database_instance" "instance" {
  project          = var.project_id
  name             = var.instance_name
  region           = var.region
  database_version = var.database_version

  settings {
    tier              = var.tier
    disk_size         = var.disk_size_gb
    disk_autoresize   = var.disk_autoresize
    availability_type = var.availability_type

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.private_network

      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
    }

    backup_configuration {
      enabled = false
    }
  }

  deletion_protection = false
  depends_on          = [google_service_networking_connection.private_service_connection]

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

resource "google_sql_database" "shared" {
  project  = var.project_id
  name     = var.shared_database_name
  instance = google_sql_database_instance.instance.name
  # Destroy database before app user (user cannot be dropped while it owns objects in the DB).
  depends_on = [google_sql_user.app_user]
}

resource "google_sql_database" "tenants" {
  for_each = toset(var.tenant_databases)
  project  = var.project_id
  name     = each.key
  instance = google_sql_database_instance.instance.name
  depends_on = [google_sql_user.app_user]
}

resource "random_password" "app_user" {
  length  = 24
  special = true
}

resource "google_sql_user" "app_user" {
  project  = var.project_id
  name     = var.app_user
  instance = google_sql_database_instance.instance.name
  password = random_password.app_user.result
}

resource "google_secret_manager_secret_version" "db_password" {
  project     = var.project_id
  secret      = var.db_password_secret_id
  secret_data = random_password.app_user.result
}
