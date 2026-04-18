# Stage 1 – assets (idempotent): Artifact Registry for the backend image and the GCS bucket for the
# built React SPA. Every resource here converges to declared state on reapply; shell-side steps in
# terraform-stage.sh (docker push, gcloud storage rsync) are likewise reentrant.

locals {
  frontend_bucket_name = coalesce(var.frontend_bucket_name, "${var.project_id}-tbd-tf-frontend-bucket")
}

resource "google_project_service" "artifactregistry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  project            = var.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  project            = var.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "docker" {
  location      = var.region
  repository_id = var.artifact_repo
  description   = "Tripplanning container images (managed by stage1)"
  format        = "DOCKER"

  # Keep the last N tagged images and remove untagged layers after a TTL so re-pushes from CI do
  # not grow storage unboundedly. Cloud Run pins by digest so deleting older tags is safe.
  cleanup_policies {
    id     = "keep-recent-tagged"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.artifact_registry_keep_tagged_count
    }
  }

  dynamic "cleanup_policies" {
    for_each = var.artifact_registry_untagged_ttl_days > 0 ? [1] : []
    content {
      id     = "delete-untagged"
      action = "DELETE"
      condition {
        tag_state  = "UNTAGGED"
        older_than = "${var.artifact_registry_untagged_ttl_days * 24}h"
      }
    }
  }

  depends_on = [google_project_service.artifactregistry]
}

resource "google_storage_bucket" "frontend" {
  name                        = local.frontend_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.frontend_bucket_force_destroy

  # SPA deep-link fallback: the backend-bucket LB returns index.html for any missing object so
  # React Router routes like /trips/123 resolve on direct hits and reloads.
  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }

  versioning {
    enabled = true
  }

  depends_on = [google_project_service.storage]
}

# Uniform bucket-level access forbids per-object ACLs; the CDN-backed backend bucket needs public
# read on the whole bucket to serve the SPA. Using _iam_member (not _iam_binding) keeps this
# authoritative on a single principal without clobbering other bindings on reruns.
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.frontend.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
