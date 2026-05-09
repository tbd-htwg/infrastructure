resource "google_storage_bucket" "buckets" {
  for_each = var.buckets

  project                     = var.project_id
  name                        = "${var.project_id}-${each.value.name_suffix}"
  location                    = var.location
  storage_class               = each.value.storage_class
  uniform_bucket_level_access = each.value.uniform_access
  force_destroy               = each.value.force_destroy

  versioning {
    enabled = each.value.versioning
  }

  dynamic "cors" {
    for_each = each.value.cors
    content {
      origin          = cors.value.origin
      method          = cors.value.method
      response_header = cors.value.response_header
      max_age_seconds = cors.value.max_age_seconds
    }
  }
}
