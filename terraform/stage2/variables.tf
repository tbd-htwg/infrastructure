variable "project_id" {
  description = "GCP project ID (billing must be enabled; project must exist)."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources (Cloud SQL, Cloud Run, serverless NEG). Match terraform_iaas/terraform_es region; place GCE VMs in a zone in this region."
  type        = string
}

variable "artifact_repo" {
  description = "Artifact Registry repository id created by stage 1. Looked up here via a data source."
  type        = string
}

variable "frontend_bucket_name" {
  description = "Override for the GCS bucket name created by stage 1. Defaults to \"<project_id>-tbd-tf-frontend-bucket\"."
  type        = string
  nullable    = true
  default     = null
}

variable "backend_image_tag" {
  description = "Artifact Registry image tag for the Cloud Run backend (usually the git short SHA written by stage 1 via terraform-stage.sh). Stage 2 constructs the full image URI from region + project_id + artifact_repo + cloud_run_backend_service_name + this tag."
  type        = string
}

variable "run_sa_name" {
  description = "Service account id (without @project.iam.gserviceaccount.com) for the Cloud Run runtime."
  type        = string
}

variable "db_instance_name" {
  description = "Cloud SQL instance name."
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name inside the instance."
  type        = string
}

variable "db_user" {
  description = "PostgreSQL application user name."
  type        = string
}

variable "db_password_secret_name" {
  description = "Secret Manager secret id storing the DB password (same value as the Cloud SQL user password)."
  type        = string
}

variable "sql_tier" {
  description = "Cloud SQL machine tier."
  type        = string
  default     = "db-custom-1-3840"
}

variable "sql_disk_size_gb" {
  description = "Initial allocated disk size (GB) for the Cloud SQL instance. Autoresize is enabled so the floor grows with usage."
  type        = number
  default     = 10
}

variable "sql_deletion_protection" {
  description = "Cloud SQL deletion protection. Production default is true; flip to false and re-apply once before running --destroy."
  type        = bool
  default     = true
}

variable "sql_high_availability" {
  description = "Set to true to provision Cloud SQL as REGIONAL (HA, synchronous standby). Default ZONAL keeps cost lower for single-zone deployments."
  type        = bool
  default     = false
}

variable "frontend_hostname" {
  description = "Public hostname for the React SPA (HTTPS LB + managed SSL)."
  type        = string
  default     = "tf.tbd-htwg.de"
}

variable "cloud_run_api_hostname" {
  description = "Public hostname for the backend API (same HTTPS LB as the SPA; routed by host rule to the serverless NEG in front of Cloud Run)."
  type        = string
  default     = "api.tf.tbd-htwg.de"
}

variable "frontend_url_map_name" {
  description = "Compute URL map name used by the HTTPS LB and by gcloud compute url-maps invalidate-cdn-cache."
  type        = string
  default     = "tbd-tf-lb"
}

variable "cloud_run_backend_service_name" {
  description = "Cloud Run service name for the API. Also used as the Docker image name under artifact_repo."
  type        = string
  default     = "tbd-tf-backend"
}

variable "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances (set 1+ to keep a warm instance and avoid cold starts on quiet services)."
  type        = number
  default     = 0
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances."
  type        = number
  default     = 10
}

variable "cloud_run_cpu" {
  description = "Cloud Run container CPU limit (e.g. \"1\", \"2\", \"4\"). Must be allowed for the chosen tier/region."
  type        = string
  default     = "1"
}

variable "cloud_run_memory" {
  description = "Cloud Run container memory limit (e.g. \"512Mi\", \"1Gi\", \"2Gi\")."
  type        = string
  default     = "1Gi"
}

variable "cloud_run_request_timeout_seconds" {
  description = "Request timeout for the Cloud Run service in seconds."
  type        = number
  default     = 60
}

variable "cors_allowed_origins" {
  description = "Comma-separated origins for CORS_ALLOWED_ORIGINS on the backend (e.g. https://frontend_hostname)."
  type        = string
  default     = ""
}

variable "dns_managed_zone_name" {
  description = "Name of an existing Cloud DNS managed zone in this project (not created/destroyed here). Used when manage_cloud_dns_records is true."
  type        = string
  default     = "tbd-example-zone"
}

variable "manage_cloud_dns_records" {
  description = "Create A records (SPA + API hostnames → LB IP) in dns_managed_zone_name. Disable to manage DNS outside Terraform."
  type        = bool
  default     = true
}

variable "enable_cloud_armor" {
  description = "Attach a Cloud Armor security policy (preconfigured OWASP WAF rules + per-IP rate limit) to the API backend service."
  type        = bool
  default     = false
}

variable "cloud_armor_rate_limit_rps" {
  description = "Per-IP request rate (requests per minute) at which Cloud Armor starts throttling, when enable_cloud_armor is true."
  type        = number
  default     = 600
}

variable "remote_elasticsearch" {
  description = <<-EOT
    When non-null, the Cloud Run backend uses Hibernate Search with Elasticsearch over HTTPS
    (e.g. dedicated ES gateway from infrastructure/terraform_es: host:443, path_prefix /es).
    password_secret_id is the Secret Manager secret *short name* in this project (terraform_es output
    elastic_password_secret_id), not the password value. Grant the Cloud Run runtime SA
    roles/secretmanager.secretAccessor (stage2 adds IAM; terraform_es may also use secret_accessor_members).
  EOT
  type = object({
    hosts              = string
    password_secret_id = string
    protocol           = optional(string, "https")
    path_prefix        = optional(string, "/es")
    username           = optional(string, "elastic")
  })
  default = null
}
