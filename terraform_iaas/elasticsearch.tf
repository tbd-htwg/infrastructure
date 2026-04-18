resource "random_password" "elasticsearch" {
  for_each = local.tiers_enabled

  length  = 32
  special = false
}

resource "google_secret_manager_secret" "elasticsearch" {
  for_each = local.tiers_enabled

  secret_id = "${var.instance_name_prefix}-elasticsearch-${each.key}"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "elasticsearch" {
  for_each = local.tiers_enabled

  secret      = google_secret_manager_secret.elasticsearch[each.key].id
  secret_data = random_password.elasticsearch[each.key].result
}

resource "google_secret_manager_secret_iam_member" "vm_elasticsearch" {
  for_each = local.tiers_enabled

  project   = var.project_id
  secret_id = google_secret_manager_secret.elasticsearch[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.iaas_vm.email}"

  depends_on = [google_service_account.iaas_vm]
}

resource "google_secret_manager_secret_iam_member" "elasticsearch_extra_accessor" {
  for_each = {
    for pair in setproduct(keys(local.tiers_enabled), var.elasticsearch_secret_accessor_members) :
    "${pair[0]}::${pair[1]}" => { tier = pair[0], member = pair[1] }
  }

  project   = var.project_id
  secret_id = google_secret_manager_secret.elasticsearch[each.value.tier].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
