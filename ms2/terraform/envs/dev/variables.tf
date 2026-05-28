variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "Default region."
  default     = "europe-west1"
}

variable "enable_dns" {
  type        = bool
  description = "Whether to create Cloud DNS managed zone."
  default     = true
}

variable "dns_zone" {
  type = object({
    name        = string
    domain      = string
    description = string
  })
  description = "Cloud DNS zone settings."
}

variable "network" {
  type = object({
    name                    = string
    subnet_name             = string
    subnet_cidr             = string
    pods_secondary_name     = string
    pods_secondary_cidr     = string
    services_secondary_name = string
    services_secondary_cidr = string
  })
  description = "Network settings for the GKE cluster."
}

variable "gke" {
  type = object({
    cluster_name           = string
    release_channel        = string
    enable_gateway_api     = bool
    private_cluster        = bool
    master_ipv4_cidr_block = string
  })
  description = "GKE Autopilot cluster settings."
}


variable "storage" {
  type = object({
    location = string
  })
  description = "Storage bucket defaults."
  default = {
    location = "EU"
  }
}

variable "kms" {
  type = object({
    enabled         = bool
    location        = string
    key_ring_name   = string
    crypto_key_name = string
  })
  description = "Optional KMS configuration."
  default = {
    enabled         = false
    location        = "europe-west1"
    key_ring_name   = "tripplanning-keyring"
    crypto_key_name = "tripplanning-key"
  }
}

variable "frontend" {
  type = object({
    domain                                 = string
    enable_cdn                             = bool
    api_backend_neg_self_link              = optional(string)
    api_paths                              = optional(list(string))
    secondary_managed_ssl_certificate_name = optional(string)
  })
  description = "Frontend bucket + HTTPS load balancer settings."
}

variable "github_wif" {
  type = object({
    owner                = string
    repo                 = string
    pool_id              = string
    provider_id          = string
    service_account_name = string
  })
  description = "GitHub Workload Identity Federation settings for frontend deploy."
}

variable "backend_wif" {
  type = object({
    owner       = string
    repo        = string
    provider_id = string
  })
  description = "GitHub Workload Identity Federation settings for backend secret sync."
}
