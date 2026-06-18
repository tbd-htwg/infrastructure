variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "frontend_domain" {
  type        = string
  description = "Public domain for the frontend (A record and SSL cert)."
}

variable "additional_frontend_domains" {
  type        = list(string)
  description = "Additional hostnames routed by the frontend HTTPS load balancer."
  default     = []
}

variable "certificate_domains" {
  type        = list(string)
  description = "Domains covered by the Certificate Manager certificate and certificate map. Wildcards are supported."

  validation {
    condition     = length(var.certificate_domains) > 0
    error_message = "certificate_domains must contain at least one domain."
  }
}

variable "host_api_backend_internet_endpoints" {
  type = map(object({
    hostnames = list(string)
    ip        = string
    port      = optional(number, 8088)
  }))
  description = "Optional host-specific API backends. Used for Enterprise tenant hosts that should serve the shared frontend but route /api/* to a dedicated tenant api-router LoadBalancer."
  default     = {}
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

variable "api_backend_internet_endpoint_ip" {
  type        = string
  description = "Optional external IP for an internet NEG API backend, for example the Standard api-router LoadBalancer IP."
  default     = null
}

variable "api_backend_internet_endpoint_port" {
  type        = number
  description = "Port for the optional internet NEG API backend."
  default     = 8088
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
