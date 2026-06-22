variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "project_number" {
  type        = string
  description = "Numeric GCP project number used by IAM workload identity resources."
}

variable "pool_id" {
  type        = string
  description = "Workload Identity Pool ID."
  default     = "github-actions"
}

variable "provider_id" {
  type        = string
  description = "Workload Identity Provider ID."
  default     = "github-oidc"
}

variable "github_owner" {
  type        = string
  description = "GitHub org/user."
}

variable "github_repo" {
  type        = string
  description = "GitHub repo name."
}

variable "service_account_name" {
  type        = string
  description = "Service account name for GitHub Actions."
  default     = "frontend-deployer"
}

variable "bucket_name" {
  type        = string
  description = "Frontend bucket name to grant access."
}

variable "url_map_name" {
  type        = string
  description = "URL map name for CDN invalidation."
}
