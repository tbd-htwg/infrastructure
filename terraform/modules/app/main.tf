locals {
  resource_suffix = var.name_prefix == "" ? "" : "-${var.name_prefix}"
  image_signer_account_id = coalesce(
    var.image_signer_account_id,
    "tripplanning-${var.env_prefix}-image-url-sig"
  )
}

# -------------------------
# SERVICE ACCOUNTS
# -------------------------
resource "google_service_account" "backend_runtime" {
  account_id   = "tripplanning-${var.env_prefix}-be-rt"
  display_name = "tripplanning ${var.env_prefix} backend runtime"
}

resource "google_service_account" "backend_deploy" {
  account_id   = "tripplanning-${var.env_prefix}-be-deploy"
  display_name = "tripplanning ${var.env_prefix} backend deployer"
}

resource "google_service_account" "frontend_deploy" {
  account_id   = "tripplanning-${var.env_prefix}-fe-deploy"
  display_name = "tripplanning ${var.env_prefix} frontend deployer"
}

resource "google_service_account" "image_signer" {
  account_id   = local.image_signer_account_id
  display_name = "tripplanning-${var.env_prefix}-image-url-signer"
  description  = "Signs image upload URLs for upload to buckets from frontend"
}

resource "google_service_account" "image_store" {
  account_id   = "tripplanning-${var.env_prefix}-img-store"
  display_name = "tripplanning ${var.env_prefix} images object store"
}

resource "google_service_account" "identity_admin" {
  account_id   = "tripplanning-${var.env_prefix}-id-admin"
  display_name = "tripplanning ${var.env_prefix} identity admin"
}

# -------------------------
# IAM
# -------------------------
resource "google_project_iam_member" "run_admin" {
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.backend_deploy.email}"
  project = var.project_id
}

resource "google_project_iam_member" "cloudsql_client" {
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.backend_runtime.email}"
  project = var.project_id
}

resource "google_project_iam_member" "datastore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.backend_runtime.email}"
}

resource "google_project_iam_member" "identitytoolkit_admin" {
  project = var.project_id
  role    = "roles/identitytoolkit.admin"
  member  = "serviceAccount:${google_service_account.identity_admin.email}"
}

resource "google_project_iam_member" "frontend_cdn_invalidator" {
  project = var.project_id
  role    = var.frontend_cdn_invalidator_role_id
  member  = "serviceAccount:${google_service_account.frontend_deploy.email}"
}

resource "google_project_iam_member" "image_signer_token_creator_project" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:${google_service_account.image_signer.email}"
}

resource "google_service_account_iam_member" "backend_runtime_can_impersonate_image_signer" {
  service_account_id = google_service_account.image_signer.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.backend_runtime.email}"
}

# -------------------------
# SECRET
# -------------------------
resource "google_secret_manager_secret_iam_member" "db_password_accessor" {
  project   = var.project_id
  secret_id = var.db_password_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend_runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "elasticsearch_password_accessor" {
  project   = var.project_id
  secret_id = var.elasticsearch_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend_runtime.email}"
}

data "google_secret_manager_secret_version" "db_password" {
  project = var.project_id
  secret  = var.db_password_secret_id
  version = "latest"
}

# -------------------------
# CLOUD SQL
# -------------------------
resource "google_sql_database_instance" "db" {
  name             = "tripplanning${local.resource_suffix}-pg"
  region           = "europe-west1"
  database_version = "POSTGRES_15"

  settings {
    tier = "db-custom-1-3840"

    disk_size = 10

    backup_configuration {
      enabled = false
    }

    enable_dataplex_integration = var.enable_dataplex_integration

    ip_configuration {
      ipv4_enabled = true
    }
  }
}

resource "google_sql_database" "app" {
  name     = var.db_name
  instance = google_sql_database_instance.db.name
}

resource "google_sql_user" "app" {
  name     = "tripplanning_app"
  instance = google_sql_database_instance.db.name
  password = data.google_secret_manager_secret_version.db_password.secret_data
}

# -------------------------
# CLOUD RUN BACKEND
# -------------------------
resource "google_cloud_run_service" "backend" {
  name     = "tripplanning${local.resource_suffix}-backend"
  location = "europe-west1"

  depends_on = [
    google_project_iam_member.cloudsql_client,
    google_secret_manager_secret_iam_member.db_password_accessor,
    google_secret_manager_secret_iam_member.elasticsearch_password_accessor,
    google_sql_database.app,
    google_sql_user.app,
  ]

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels,
      template[0].metadata[0].annotations,
      template[0].metadata[0].labels,
    ]
  }

  template {
    spec {
      service_account_name = google_service_account.backend_runtime.email

      containers {
        image = var.backend_image

        env {
          name  = "SPRING_DATASOURCE_URL"
          value = "jdbc:postgresql:///${var.db_name}?socketFactory=com.google.cloud.sql.postgres.SocketFactory&cloudSqlInstance=${google_sql_database_instance.db.connection_name}"
        }

        env {
          name  = "SPRING_DATASOURCE_USERNAME"
          value = "tripplanning_app"
        }

        env {
          name  = "SPRING_DATASOURCE_DRIVER_CLASS_NAME"
          value = "org.postgresql.Driver"
        }

        env {
          name = "SPRING_DATASOURCE_PASSWORD"
          value_from {
            secret_key_ref {
              name = var.db_password_secret_id
              key  = "latest"
            }
          }
        }

        env {
          name  = "CORS_ALLOWED_ORIGINS"
          value = "https://${var.domain_main}"
        }

        env {
          name  = "ELASTICSEARCH_PROTOCOL"
          value = var.elasticsearch_protocol
        }

        env {
          name  = "ELASTICSEARCH_HOSTS"
          value = var.elasticsearch_hosts
        }

        env {
          name  = "ELASTICSEARCH_USERNAME"
          value = var.elasticsearch_username
        }

        env {
          name  = "ELASTICSEARCH_PATH_PREFIX"
          value = var.elasticsearch_path_prefix
        }

        env {
          name  = "TRIPPLANNING_SEARCH_ELASTICSEARCH_INDEX_NAME"
          value = var.search_index_name
        }

        env {
          name  = "TRIPPLANNING_AUTH_FIREBASE_PROJECT_ID"
          value = var.firebase_project_id
        }

        env {
          name  = "TRIPPLANNING_AUTH_JWT_SECRET"
          value = var.jwt_secret
        }

        env {
          name  = "SPRING_CLOUD_GCP_IMPERSONATE_SERVICE_ACCOUNT"
          value = google_service_account.image_signer.email
        }

        env {
          name = "ELASTICSEARCH_PASSWORD"
          value_from {
            secret_key_ref {
              name = var.elasticsearch_secret_id
              key  = "latest"
            }
          }
        }
      }
    }

    metadata {
      annotations = {
        "run.googleapis.com/cloudsql-instances" = google_sql_database_instance.db.connection_name
      }
    }

  }
}

# -------------------------
# STORAGE (FRONTEND)
# -------------------------
resource "google_storage_bucket" "frontend" {
  name                        = var.frontend_bucket_name
  location                    = "EU"
  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }
}

resource "google_storage_bucket_iam_member" "frontend_deploy_bucket_viewer" {
  bucket = google_storage_bucket.frontend.name
  role   = "roles/storage.bucketViewer"
  member = "serviceAccount:${google_service_account.frontend_deploy.email}"
}

resource "google_storage_bucket_iam_member" "frontend_deploy_object_admin" {
  bucket = google_storage_bucket.frontend.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.frontend_deploy.email}"
}

resource "google_storage_bucket_iam_member" "image_bucket_backend_object_admin" {
  bucket = var.image_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.backend_runtime.email}"
}

resource "google_storage_bucket_iam_member" "image_bucket_store_bucket_viewer" {
  bucket = var.image_bucket_name
  role   = "roles/storage.bucketViewer"
  member = "serviceAccount:${google_service_account.image_store.email}"
}

resource "google_storage_bucket_iam_member" "image_bucket_store_object_admin" {
  bucket = var.image_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.image_store.email}"
}

resource "google_storage_bucket_iam_member" "image_bucket_signer_object_creator" {
  bucket = var.image_bucket_name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.image_signer.email}"
}

resource "google_storage_bucket_iam_member" "image_bucket_signer_object_viewer" {
  bucket = var.image_bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.image_signer.email}"
}

resource "google_cloud_run_service" "frontend" {
  count    = var.frontend_run_image == null ? 0 : 1
  name     = "tripplanning${local.resource_suffix}-frontend"
  location = "europe-west1"

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels,
      template[0].metadata[0].annotations,
      template[0].metadata[0].labels,
    ]
  }

  template {
    spec {
      service_account_name = var.frontend_run_service_account_email

      containers {
        image = var.frontend_run_image
      }
    }
  }
}

# -------------------------
# LOAD BALANCER (FULL)
# -------------------------

# SSL Cert
resource "google_compute_managed_ssl_certificate" "cert" {
  name = var.ssl_cert_name

  managed {
    domains = [
      var.domain_main,
      var.domain_api
    ]
  }
}

# Serverless NEG
resource "google_compute_region_network_endpoint_group" "backend_neg" {
  name                  = var.backend_neg_name
  network_endpoint_type = "SERVERLESS"
  region                = "europe-west1"

  cloud_run {
    service = google_cloud_run_service.backend.name
  }
}

# Backend service (API)
resource "google_compute_backend_service" "api_backend" {
  name                            = "tripplanning${local.resource_suffix}-api-backend"
  protocol                        = "HTTP"
  load_balancing_scheme           = "EXTERNAL"
  connection_draining_timeout_sec = 0

  backend {
    group = google_compute_region_network_endpoint_group.backend_neg.id
  }
}

# Backend bucket (frontend)
resource "google_compute_backend_bucket" "frontend_backend" {
  name        = "tripplanning${local.resource_suffix}-frontend-backend"
  bucket_name = google_storage_bucket.frontend.name
  enable_cdn  = true
}

# URL map
resource "google_compute_url_map" "lb" {
  name = "tripplanning${local.resource_suffix}-lb"

  default_service = google_compute_backend_bucket.frontend_backend.id

  host_rule {
    hosts        = [var.domain_main]
    path_matcher = "path-matcher-frontend"
  }

  host_rule {
    hosts        = [var.domain_api]
    path_matcher = "path-matcher-backend"
  }

  path_matcher {
    name            = "path-matcher-frontend"
    default_service = google_compute_backend_bucket.frontend_backend.id
  }

  path_matcher {
    name            = "path-matcher-backend"
    default_service = google_compute_backend_service.api_backend.id
  }
}

# HTTPS proxy
resource "google_compute_target_https_proxy" "https" {
  name             = "tripplanning${local.resource_suffix}-lb-https-proxy"
  url_map          = google_compute_url_map.lb.id
  ssl_certificates = [google_compute_managed_ssl_certificate.cert.id]
}

# Forwarding rule
resource "google_compute_global_forwarding_rule" "https" {
  name                  = "tripplanning${local.resource_suffix}-lb-https-rule"
  target                = google_compute_target_https_proxy.https.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL"
}

# DNS records
resource "google_dns_record_set" "main" {
  name         = "${var.domain_main}."
  type         = "A"
  ttl          = 300
  managed_zone = "tbd-example-zone"

  rrdatas = [google_compute_global_forwarding_rule.https.ip_address]
}

resource "google_dns_record_set" "api" {
  name         = "${var.domain_api}."
  type         = "A"
  ttl          = 300
  managed_zone = "tbd-example-zone"

  rrdatas = [google_compute_global_forwarding_rule.https.ip_address]
}

resource "google_cloud_run_domain_mapping" "frontend" {
  count    = var.manage_cloud_run_domain_mappings && var.frontend_run_image != null ? 1 : 0
  name     = var.domain_main
  location = "europe-west1"

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_service.frontend[0].name
  }
}

resource "google_cloud_run_domain_mapping" "api" {
  count    = var.manage_cloud_run_domain_mappings ? 1 : 0
  name     = var.domain_api
  location = "europe-west1"

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_service.backend.name
  }
}
