# Cloud Run: backend API. The React app is served from GCS + CDN (see frontend_static.tf).
# The image URI is derived from the stage 1 Artifact Registry data source + the service name
# + the tag variable so callers only have to pass backend_image_tag.

locals {
  backend_jdbc_url = "jdbc:postgresql:///${var.db_name}?socketFactory=com.google.cloud.sql.postgres.SocketFactory&cloudSqlInstance=${google_sql_database_instance.main.connection_name}"

  backend_image = "${var.region}-docker.pkg.dev/${var.project_id}/${data.google_artifact_registry_repository.docker.repository_id}/${var.cloud_run_backend_service_name}:${var.backend_image_tag}"

  use_remote_elasticsearch = var.remote_elasticsearch != null

  search_env_static = local.use_remote_elasticsearch ? [
    { name = "SPRING_JPA_PROPERTIES_HIBERNATE_SEARCH_BACKEND_TYPE", value = "elasticsearch" },
    { name = "SPRING_JPA_PROPERTIES_HIBERNATE_SEARCH_BACKEND_PROTOCOL", value = var.remote_elasticsearch.protocol },
    { name = "SPRING_JPA_PROPERTIES_HIBERNATE_SEARCH_BACKEND_HOSTS", value = var.remote_elasticsearch.hosts },
    { name = "SPRING_JPA_PROPERTIES_HIBERNATE_SEARCH_BACKEND_PATH_PREFIX", value = var.remote_elasticsearch.path_prefix },
    { name = "SPRING_JPA_PROPERTIES_HIBERNATE_SEARCH_BACKEND_USERNAME", value = var.remote_elasticsearch.username },
    ] : [
    { name = "SPRING_JPA_PROPERTIES_HIBERNATE_SEARCH_BACKEND_TYPE", value = "lucene" },
    { name = "SPRING_JPA_PROPERTIES_HIBERNATE_SEARCH_BACKEND_DIRECTORY_ROOT", value = "/tmp/tripplanning-search" },
    { name = "SPRING_JPA_PROPERTIES_HIBERNATE_SEARCH_BACKEND_ANALYSIS_CONFIGURER", value = "class:com.tripplanning.search.LuceneEnglishAnalysisConfigurer" },
  ]
}

resource "google_cloud_run_v2_service" "backend" {
  name     = var.cloud_run_backend_service_name
  location = var.region
  project  = var.project_id

  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    service_account                  = google_service_account.cloud_run.email
    execution_environment            = "EXECUTION_ENVIRONMENT_GEN2"
    timeout                          = "${var.cloud_run_request_timeout_seconds}s"
    max_instance_request_concurrency = 80

    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      image = local.backend_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      startup_probe {
        tcp_socket {
          port = 8080
        }
        initial_delay_seconds = 5
        timeout_seconds       = 3
        period_seconds        = 5
        failure_threshold     = 30
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      env {
        name  = "SPRING_DATASOURCE_URL"
        value = local.backend_jdbc_url
      }
      env {
        name  = "SPRING_DATASOURCE_USERNAME"
        value = var.db_user
      }
      env {
        name  = "SPRING_DATASOURCE_DRIVER_CLASS_NAME"
        value = "org.postgresql.Driver"
      }
      env {
        name  = "CORS_ALLOWED_ORIGINS"
        value = var.cors_allowed_origins
      }

      dynamic "env" {
        for_each = local.search_env_static
        content {
          name  = env.value.name
          value = env.value.value
        }
      }

      dynamic "env" {
        for_each = local.use_remote_elasticsearch ? [1] : []
        content {
          name = "SPRING_JPA_PROPERTIES_HIBERNATE_SEARCH_BACKEND_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = var.remote_elasticsearch.password_secret_id
              version = "latest"
            }
          }
        }
      }

      env {
        name = "SPRING_DATASOURCE_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  # google_cloud_run_v2_service.depends_on must be a static list (no concat/values).
  # Ensure ES password Secret Manager IAM is applied before the service mounts that secret.
  depends_on = [
    google_project_service.run,
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_iam_member.cloud_run_elasticsearch_password,
  ]
}

resource "google_secret_manager_secret_iam_member" "cloud_run_elasticsearch_password" {
  for_each = var.remote_elasticsearch != null ? { elasticsearch = var.remote_elasticsearch } : {}

  project   = var.project_id
  secret_id = each.value.password_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run.email}"
}

resource "google_cloud_run_v2_service_iam_member" "backend_invoker_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
