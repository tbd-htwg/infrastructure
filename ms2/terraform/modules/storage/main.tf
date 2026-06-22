resource "google_storage_bucket" "buckets" {
  for_each = var.buckets

  project                     = var.project_id
  name                        = coalesce(try(each.value.name, null), "${var.project_id}-${each.value.name_suffix}")
  location                    = var.location
  storage_class               = each.value.storage_class
  uniform_bucket_level_access = each.value.uniform_access
  force_destroy               = each.value.force_destroy

  versioning {
    enabled = each.value.versioning
  }

  public_access_prevention = each.value.public_access_prevention

  dynamic "retention_policy" {
    for_each = each.value.retention_period_seconds == null ? [] : [each.value.retention_period_seconds]
    content {
      retention_period = retention_policy.value
    }
  }

  dynamic "soft_delete_policy" {
    for_each = each.value.soft_delete_retention_seconds == null ? [] : [each.value.soft_delete_retention_seconds]
    content {
      retention_duration_seconds = soft_delete_policy.value
    }
  }

  dynamic "website" {
    for_each = each.value.website == null ? [] : [each.value.website]
    content {
      main_page_suffix = website.value.main_page_suffix
      not_found_page   = try(website.value.not_found_page, null)
    }
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

resource "google_storage_bucket_iam_member" "public_read" {
  for_each = { for key, bucket in var.buckets : key => bucket if try(bucket.public_read, false) }

  bucket = google_storage_bucket.buckets[each.key].name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
