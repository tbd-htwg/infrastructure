variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "frontend_domain" {
  type        = string
  description = "Public domain for the frontend (A record and SSL cert)."
}

variable "dns_zone_name" {
  type        = string
  description = "Cloud DNS managed zone name."
}

variable "bucket_name" {
  type        = string
  description = "Frontend bucket name."
}

variable "enable_cdn" {
  type        = bool
  description = "Enable Cloud CDN on the backend bucket."
  default     = false
}
