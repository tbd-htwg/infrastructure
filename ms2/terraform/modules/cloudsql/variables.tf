variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "Region for Cloud SQL."
}

variable "instance_name" {
  type        = string
  description = "Cloud SQL instance name."
}

variable "database_version" {
  type        = string
  description = "Cloud SQL database version."
  default     = "POSTGRES_15"
}

variable "tier" {
  type        = string
  description = "Cloud SQL machine tier."
  default     = "db-custom-1-3840"
}

variable "disk_size_gb" {
  type        = number
  description = "Initial disk size in GB."
  default     = 10
}

variable "disk_autoresize" {
  type        = bool
  description = "Whether to enable disk autoresize."
  default     = false
}

variable "availability_type" {
  type        = string
  description = "Availability type (ZONAL or REGIONAL)."
  default     = "ZONAL"
}

variable "private_network" {
  type        = string
  description = "VPC self link for private IP."
}

variable "private_ip_range" {
  type        = string
  description = "Base IP address for private services access (no CIDR suffix)."
  default     = "10.40.0.0/16"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.private_ip_range))
    error_message = "private_ip_range must be a base IP address like 10.40.0.0 (no CIDR)."
  }
}

variable "shared_database_name" {
  type        = string
  description = "Shared database name for free tier."
  default     = "tripplanning"
}

variable "tenant_databases" {
  type        = list(string)
  description = "Database names for paid tenants."
  default     = []
}

variable "app_user" {
  type        = string
  description = "Application database user."
  default     = "tripplanning_app"
}

variable "db_password_secret_id" {
  type        = string
  description = "Secret Manager secret ID for the DB password."
  default     = "tripplanning-db-password"
}

variable "authorized_networks" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "Optional public IP authorized networks."
  default     = []
}
