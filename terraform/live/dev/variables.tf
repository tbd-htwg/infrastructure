variable "project_id" {
  description = "GCP project ID"
}

variable "name_prefix" {
  description = "Resource name prefix (dev or empty for prod-style names)"
}

variable "backend_image" {
  description = "Docker image for backend"
}

variable "db_name" {
  description = "Cloud SQL database name"
}

variable "frontend_bucket_name" {
  description = "Frontend bucket name"
}

variable "db_password_secret_id" {
  description = "Secret Manager secret ID for DB password"
}

variable "elasticsearch_secret_id" {
  description = "Secret Manager secret ID for Elasticsearch password"
}

variable "elasticsearch_protocol" {
  description = "Elasticsearch protocol"
}

variable "elasticsearch_hosts" {
  description = "Elasticsearch hosts"
}

variable "elasticsearch_username" {
  description = "Elasticsearch username"
}

variable "elasticsearch_path_prefix" {
  description = "Elasticsearch path prefix"
}

variable "search_index_name" {
  description = "Elasticsearch index name"
}

variable "firebase_project_id" {
  description = "Firebase project ID"
}

variable "jwt_secret" {
  description = "JWT secret for auth"
  sensitive   = true
}

variable "ssl_cert_name" {
  description = "Managed SSL certificate name"
}

variable "backend_neg_name" {
  description = "Backend NEG name"
}

variable "enable_dataplex_integration" {
  description = "Enable Dataplex integration for Cloud SQL"
}

variable "image_signer_account_id" {
  description = "Service account ID for image URL signing"
  default     = "tripplanning-dev-image-url-sig"
}
