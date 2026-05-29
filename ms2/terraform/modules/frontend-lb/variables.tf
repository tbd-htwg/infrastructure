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

variable "network_self_link" {
  type        = string
  description = "VPC network self link for API backend health-check firewall rules."
}

variable "enable_cdn" {
  type        = bool
  description = "Enable Cloud CDN on the backend bucket."
  default     = false
}

variable "api_backend_neg_self_links" {
  type        = list(string)
  description = "Optional NEG self links for the API backend (one per zone where api-router pods may run)."
  default     = []
}

variable "api_backend_neg_self_link" {
  type        = string
  description = "Deprecated: single NEG self link. Use api_backend_neg_self_links instead."
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
  default     = "/actuator/health/readiness"
}

variable "api_health_check_port" {
  type        = number
  description = "HTTP health check port for the API backend."
  default     = 8080
}

variable "secondary_managed_ssl_certificate_name" {
  type        = string
  description = "Optional second managed SSL certificate name for zero-downtime rotation."
  default     = null
}
