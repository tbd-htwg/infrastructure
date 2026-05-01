variable "project_id" {}
variable "name_prefix" {}
variable "env_prefix" {}
variable "backend_image" {}
variable "domain_main" {}
variable "domain_api" {}
variable "db_name" {}
variable "frontend_bucket_name" {}
variable "db_password_secret_id" {}
variable "elasticsearch_secret_id" {}
variable "elasticsearch_protocol" {}
variable "elasticsearch_hosts" {}
variable "elasticsearch_username" {}
variable "elasticsearch_path_prefix" {}
variable "search_index_name" {}
variable "firebase_project_id" {}
variable "jwt_secret" {}
variable "ssl_cert_name" {}
variable "backend_neg_name" {}
variable "enable_dataplex_integration" {}

variable "image_signer_account_id" {
  default = null
}

variable "image_bucket_name" {
  default = "project-9118634e-c9f1-4f29-804-images-bucket"
}

variable "frontend_cdn_invalidator_role_id" {
  default = "projects/project-9118634e-c9f1-4f29-804/roles/tripplanningFrontendCdnInvalidator"
}

variable "frontend_run_image" {
  default = null
}

variable "frontend_run_service_account_email" {
  default = null
}

variable "manage_cloud_run_domain_mappings" {
  default = false
}
