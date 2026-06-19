resource "google_gke_hub_membership" "cluster" {
  project       = var.project_id
  location      = "global"
  membership_id = var.membership_id

  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${var.cluster_id}"
    }
  }
}

resource "google_gke_hub_feature" "service_mesh" {
  project  = var.project_id
  location = "global"
  name     = "servicemesh"

  fleet_default_member_config {
    mesh {
      management = "MANAGEMENT_AUTOMATIC"
    }
  }

  depends_on = [
    google_gke_hub_membership.cluster,
  ]
}

resource "google_gke_hub_feature_membership" "service_mesh" {
  project    = var.project_id
  location   = "global"
  feature    = google_gke_hub_feature.service_mesh.name
  membership = google_gke_hub_membership.cluster.membership_id

  mesh {
    management = "MANAGEMENT_AUTOMATIC"
  }
}
