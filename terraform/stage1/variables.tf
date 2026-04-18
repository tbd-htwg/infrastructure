variable "project_id" {
  description = "GCP project ID (billing must be enabled; project must exist)."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources (Artifact Registry, GCS bucket). Use the same value for stage2, terraform_iaas, and terraform_es so all workloads stay in one European region."
  type        = string
}

variable "artifact_repo" {
  description = "Artifact Registry repository id for Docker images."
  type        = string
}

variable "frontend_bucket_name" {
  description = "Override the GCS bucket name for the React app. Defaults to \"<project_id>-tbd-tf-frontend-bucket\" (same convention stage2 looks up by data source)."
  type        = string
  nullable    = true
  default     = null
}

variable "frontend_bucket_force_destroy" {
  description = "Allow deleting the frontend GCS bucket even when non-empty. For teardown: set true, run stage 1 apply once, then --destroy."
  type        = bool
  default     = false
}

variable "artifact_registry_keep_tagged_count" {
  description = "Number of most recent tagged images to keep in the Artifact Registry repo cleanup policy. Older tagged images are deleted. Set high enough to cover active release windows."
  type        = number
  default     = 20
}

variable "artifact_registry_untagged_ttl_days" {
  description = "Delete untagged Artifact Registry images older than this many days (cleanup policy). 0 keeps them indefinitely."
  type        = number
  default     = 7
}
