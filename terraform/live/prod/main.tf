terraform {
  backend "gcs" {
    bucket = "project-9118634e-c9f1-4f29-804-tf-state"
    prefix = "prod"
  }
}

provider "google" {
  project = var.project_id
  region  = "europe-west1"
}

module "app" {
  source = "../../modules/app"

  project_id                         = var.project_id
  name_prefix                        = var.name_prefix
  env_prefix                         = "prod"
  backend_image                      = var.backend_image
  domain_main                        = "paas.tbd-htwg.de"
  domain_api                         = "api.paas.tbd-htwg.de"
  db_name                            = var.db_name
  frontend_bucket_name               = var.frontend_bucket_name
  db_password_secret_id              = var.db_password_secret_id
  elasticsearch_secret_id            = var.elasticsearch_secret_id
  elasticsearch_protocol             = var.elasticsearch_protocol
  elasticsearch_hosts                = var.elasticsearch_hosts
  elasticsearch_username             = var.elasticsearch_username
  elasticsearch_path_prefix          = var.elasticsearch_path_prefix
  search_index_name                  = var.search_index_name
  firebase_project_id                = var.firebase_project_id
  jwt_secret                         = var.jwt_secret
  ssl_cert_name                      = var.ssl_cert_name
  backend_neg_name                   = var.backend_neg_name
  enable_dataplex_integration        = var.enable_dataplex_integration
  image_signer_account_id            = var.image_signer_account_id
  frontend_run_image                 = var.frontend_run_image
  frontend_run_service_account_email = var.frontend_run_service_account_email
  manage_cloud_run_domain_mappings   = var.manage_cloud_run_domain_mappings
}
