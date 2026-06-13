variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "slug" {
  type        = string
  description = "Tenant slug."
}

variable "tier" {
  type        = string
  description = "STANDARD or ENTERPRISE."

  validation {
    condition     = contains(["STANDARD", "ENTERPRISE"], var.tier)
    error_message = "tier must be STANDARD or ENTERPRISE."
  }
}

variable "dns_zone_name" {
  type        = string
  description = "Cloud DNS managed zone name."
}

variable "host_base" {
  type        = string
  description = "Standard pool apex, e.g. k8s.tbd-htwg.de."
}

variable "enterprise_host_base" {
  type        = string
  description = "Enterprise apex, e.g. enterprise.k8s.tbd-htwg.de."
}

variable "standard_lb_ip" {
  type        = string
  description = "Shared Standard pool load balancer IP."
  default     = ""
}

variable "enterprise_lb_ip" {
  type        = string
  description = "Per-tenant Enterprise load balancer IP."
  default     = ""
}
