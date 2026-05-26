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

variable "api_backend_neg_self_link" {
  type        = string
  description = "Optional NEG self link for the API backend."
  default     = null
}

variable "api_paths" {
  type        = list(string)
  description = "Path patterns routed to the API backend."
  default     = ["/api/*"]
}

variable "api_health_check_path" {
  type        = string
  description = "HTTP health check path for the API backend."
  default     = "/healthz"
}

variable "api_health_check_port" {
  type        = number
  description = "HTTP health check port for the API backend."
  default     = 8080
}
