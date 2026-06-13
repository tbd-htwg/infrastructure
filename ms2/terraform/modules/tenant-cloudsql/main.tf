resource "google_compute_global_address" "private_service_range" {
  count = var.create_private_service_connection ? 1 : 0

  project       = var.project_id
  name          = "${var.instance_name}-private-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.private_network
  address       = var.private_ip_range
}

resource "google_service_networking_connection" "private_service_connection" {
  count = var.create_private_service_connection ? 1 : 0

  network                 = var.private_network
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range[0].name]
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
    user_labels       = var.labels

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.private_network
    }

    backup_configuration {
      enabled                        = var.backup_enabled
      point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
    }
  }

  deletion_protection = false

  depends_on = [
    google_service_networking_connection.private_service_connection,
  ]
}

resource "google_sql_database" "databases" {
  for_each = var.databases

  project  = var.project_id
  name     = each.value.name
  instance = google_sql_database_instance.instance.name
}

resource "random_password" "db_users" {
  for_each = var.databases

  length  = 24
  special = true
}

resource "google_sql_user" "db_users" {
  for_each = var.databases

  project  = var.project_id
  name     = each.value.user_name
  instance = google_sql_database_instance.instance.name
  password = random_password.db_users[each.key].result
}

resource "google_secret_manager_secret" "db_passwords" {
  for_each = var.databases

  project   = var.project_id
  secret_id = each.value.password_secret_id
  labels    = var.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_passwords" {
  for_each = var.databases

  project     = var.project_id
  secret      = google_secret_manager_secret.db_passwords[each.key].id
  secret_data = random_password.db_users[each.key].result
}
