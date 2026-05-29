locals {
  enabled_apis = toset(var.api_services)
}

resource "google_project_service" "apis" {
  for_each           = local.enabled_apis
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_firestore_database" "database" {
  count       = var.firestore.enabled ? 1 : 0
  project     = var.project_id
  name        = var.firestore.database_id
  location_id = var.firestore.location_id
  type        = var.firestore.type

  depends_on = [
    google_project_service.apis["firestore.googleapis.com"],
  ]
}

resource "google_firestore_index" "indexes" {
  for_each    = var.firestore.enabled ? var.firestore.indexes : {}
  project     = var.project_id
  database    = var.firestore.database_id
  collection  = each.value.collection
  query_scope = each.value.query_scope

  dynamic "fields" {
    for_each = each.value.fields
    content {
      field_path = fields.value.field_path
      order      = fields.value.order
    }
  }

  depends_on = [
    google_firestore_database.database,
  ]
}

resource "google_service_account" "service_accounts" {
  for_each     = var.service_accounts
  project      = var.project_id
  account_id   = replace(each.key, "_", "-")
  display_name = each.value.display_name
  description  = each.value.description
}

resource "google_project_iam_binding" "bindings" {
  for_each = var.iam_bindings
  project  = var.project_id
  role     = each.key
  members  = each.value
}

resource "google_artifact_registry_repository" "repo" {
  count         = var.artifact_registry_enabled ? 1 : 0
  project       = var.project_id
  location      = var.artifact_registry.location
  repository_id = var.artifact_registry.name
  format        = var.artifact_registry.format
  description   = var.artifact_registry.description
}

resource "google_secret_manager_secret" "secrets" {
  for_each  = { for secret in var.secrets : secret.name => secret }
  project   = var.project_id
  secret_id = each.key

  labels = each.value.labels

  replication {
    auto {}
  }
}

resource "google_dns_managed_zone" "zone" {
  count       = var.enable_dns ? 1 : 0
  project     = var.project_id
  name        = var.dns_zone.name
  dns_name    = var.dns_zone.domain
  description = var.dns_zone.description
}

resource "google_storage_bucket" "log_sink" {
  count                       = var.log_sink.enabled ? 1 : 0
  project                     = var.project_id
  name                        = "${var.project_id}-${var.log_sink.name}"
  location                    = var.log_sink.bucket_location
  uniform_bucket_level_access = true
}

resource "google_logging_project_sink" "log_sink" {
  count       = var.log_sink.enabled ? 1 : 0
  project     = var.project_id
  name        = var.log_sink.name
  destination = "storage.googleapis.com/${google_storage_bucket.log_sink[0].name}"
  filter      = var.log_sink.filter
}

resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count  = var.log_sink.enabled ? 1 : 0
  bucket = google_storage_bucket.log_sink[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.log_sink[0].writer_identity
}
