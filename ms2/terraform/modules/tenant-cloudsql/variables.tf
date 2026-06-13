variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "Cloud SQL region."
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
  description = "Whether Cloud SQL can grow disk automatically."
  default     = true
}

variable "availability_type" {
  type        = string
  description = "Cloud SQL availability type: ZONAL or REGIONAL."
  default     = "ZONAL"
}

variable "backup_enabled" {
  type        = bool
  description = "Whether automated backups are enabled."
  default     = true
}

variable "point_in_time_recovery_enabled" {
  type        = bool
  description = "Whether point-in-time recovery is enabled."
  default     = false
}

variable "private_network" {
  type        = string
  description = "VPC self link for private IP."
}

variable "create_private_service_connection" {
  type        = bool
  description = "Whether this module creates the private services access range/connection."
  default     = false
}

variable "private_ip_range" {
  type        = string
  description = "Base private services access address, without CIDR suffix."
  default     = "10.40.0.0"
}

variable "databases" {
  type = map(object({
    name               = string
    user_name          = string
    password_secret_id = string
  }))
  description = "Databases, app users, and password secrets to create."
  default     = {}
}

variable "labels" {
  type        = map(string)
  description = "Labels for supported resources."
  default     = {}
}
